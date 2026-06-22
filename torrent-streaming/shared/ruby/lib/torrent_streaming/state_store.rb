# frozen_string_literal: true

# Durable JSON persistence for the shared Ruby state model. Records are grouped
# by family, validated through the domain layer, and written with atomic file
# replacement so API and worker processes see complete records only.
require "fileutils"
require "json"
require "securerandom"
require "time"

require_relative "domain"
require_relative "errors"
require_relative "validation"

module TorrentStreaming
  # Persists media and session records under storage/state using per-record
  # locks. Corrupt JSON is copied aside before an error is raised so operators
  # can inspect the bad state without the next write silently overwriting it.
  class StateStore
    FAMILIES = {
      media: {
        dir: "media",
        validator: ->(id) { Validation.media_id!(id) },
        domain_validator: ->(record) { Media.validate!(record) }
      },
      sessions: {
        dir: "sessions",
        validator: ->(id) { Validation.session_id!(id) },
        domain_validator: ->(record) { PlaybackSession.validate!(record) }
      }
    }.freeze

    attr_reader :root

    def initialize(root:)
      @root = File.expand_path(root)
      prepare_directories
    end

    # Reads validate both JSON shape and domain shape before returning a record.
    def read(family, id)
      config = family_config(family)
      safe_id = config.fetch(:validator).call(id)
      path = record_path(config, safe_id)
      raise NotFoundError, "#{family} #{safe_id} not found" unless File.file?(path)

      read_json(path, config)
    end

    # Serializes all writes for a record, rereads the current file under that
    # lock, validates the yielded replacement, and commits it with atomic rename.
    # The reread avoids applying an update to stale state when another process
    # wrote the same record just before the lock was acquired.
    def write(family, id)
      config = family_config(family)
      safe_id = config.fetch(:validator).call(id)
      path = record_path(config, safe_id)

      with_lock(family, safe_id) do
        current = File.file?(path) ? read_json(path, config) : nil
        next_record = yield current
        config.fetch(:domain_validator).call(next_record)
        atomic_write_json(path, next_record)
        next_record
      end
    end

    def exist?(family, id)
      config = family_config(family)
      safe_id = config.fetch(:validator).call(id)
      File.file?(record_path(config, safe_id))
    end

    def all(family)
      config = family_config(family)
      pattern = File.join(root, config.fetch(:dir), "*.json")
      Dir.glob(pattern).sort.map { |path| read_json(path, config) }
    end

    private

    def prepare_directories
      (FAMILIES.values.map { |config| config.fetch(:dir) } + %w[locks corrupt]).each do |dir|
        FileUtils.mkdir_p(File.join(root, dir))
      end
    end

    def family_config(family)
      FAMILIES.fetch(family.to_sym)
    rescue KeyError
      raise ValidationError.new("unknown state family #{family}", code: "unknown_state_family")
    end

    def record_path(config, id)
      File.join(root, config.fetch(:dir), "#{id}.json")
    end

    def lock_path(family, id)
      File.join(root, "locks", "#{family}-#{id}.lock")
    end

    # The lock file name is built only from family names and validated IDs, so
    # the lock path cannot escape the state root.
    def with_lock(family, id)
      File.open(lock_path(family, id), File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      ensure
        lock.flock(File::LOCK_UN)
      end
    end

    # Invalid JSON is treated as an operational fault, not an empty record.
    # Preserving the bytes first prevents a later successful write from erasing
    # the evidence needed to diagnose a partial write or manual edit.
    def read_json(path, config)
      raw = File.read(path, encoding: "utf-8")
      record = JSON.parse(raw)
      unless record.is_a?(Hash)
        corrupt_path = preserve_corrupt(path)
        raise CorruptJsonError.new(path: path, corrupt_path: corrupt_path, cause_message: "JSON root must be an object")
      end
      raise SchemaVersionError unless record["schema_version"] == 1

      config.fetch(:domain_validator).call(record)
      record
    rescue JSON::ParserError => e
      corrupt_path = preserve_corrupt(path)
      raise CorruptJsonError.new(path: path, corrupt_path: corrupt_path, cause_message: e.message)
    end

    # Corrupt snapshots get unique names so repeated read attempts do not race
    # with each other or overwrite earlier forensic copies.
    def preserve_corrupt(path)
      FileUtils.mkdir_p(File.join(root, "corrupt"))
      basename = File.basename(path, ".json")
      stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S%6NZ")
      corrupt_path = File.join(root, "corrupt", "#{basename}.#{stamp}.#{Process.pid}.#{SecureRandom.hex(4)}.json")
      FileUtils.cp(path, corrupt_path, preserve: true)
      corrupt_path
    end

    # Writes JSON through a temp file in the target directory, fsyncs the file,
    # renames it over the old record, then fsyncs the directory when the host
    # filesystem supports it. Keeping the temp file beside the target preserves
    # atomic rename semantics across API and worker processes.
    def atomic_write_json(path, record)
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir)
      temp_path = File.join(dir, ".#{File.basename(path)}.#{Process.pid}.#{SecureRandom.hex(8)}.tmp")
      json = "#{JSON.pretty_generate(record)}\n"

      File.open(temp_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(json)
        file.flush
        file.fsync
      end
      File.rename(temp_path, path)
      fsync_dir(dir)
    ensure
      FileUtils.rm_f(temp_path) if temp_path && File.exist?(temp_path)
    end

    # Some mounted filesystems reject directory fsync; the record has already
    # been file-fsynced and renamed, so this best-effort durability step should
    # not turn a successful write into an application failure.
    def fsync_dir(dir)
      File.open(dir, File::RDONLY) { |file| file.fsync }
    rescue SystemCallError, IOError
      nil
    end
  end

  # Domain-specific facade for media records.
  class MediaStore
    def initialize(root:)
      @store = StateStore.new(root: root)
    end

    # Creating the same canonical magnet is idempotent; a hash collision with a
    # different magnet is rejected instead of reusing the existing record.
    def create_from_magnet(magnet)
      record = Media.build_from_magnet(magnet)
      @store.write(:media, record.fetch("media_id")) do |current|
        if current
          unless current.fetch("magnet") == record.fetch("magnet")
            raise ValidationError.new("media_id collision with different magnet", code: "duplicate_media_conflict")
          end
          current
        else
          record
        end
      end
    end

    def find(media_id)
      @store.read(:media, media_id)
    end

    def update(media_id)
      @store.write(:media, media_id) do |current|
        raise NotFoundError, "media #{media_id} not found" unless current

        yield current
      end
    end

    def exist?(media_id)
      @store.exist?(:media, media_id)
    end

    def all
      @store.all(:media)
    end
  end

  # Domain-specific facade for playback session records.
  class SessionStore
    def initialize(root:)
      @store = StateStore.new(root: root)
    end

    def create(media_id:, file_index:, start_time_seconds:, selected_audio: nil, selected_subtitle: nil,
               session_id: nil, playlist_path: nil, supersedes_session_id: nil,
               replaced_active_session_id: nil)
      record = PlaybackSession.build(
        media_id: media_id,
        file_index: file_index,
        start_time_seconds: start_time_seconds,
        selected_audio: selected_audio,
        selected_subtitle: selected_subtitle,
        session_id: session_id,
        playlist_path: playlist_path,
        supersedes_session_id: supersedes_session_id,
        replaced_active_session_id: replaced_active_session_id
      )
      @store.write(:sessions, record.fetch("session_id")) { record }
    end

    def find(session_id)
      @store.read(:sessions, session_id)
    end

    def update(session_id)
      @store.write(:sessions, session_id) do |current|
        raise NotFoundError, "session #{session_id} not found" unless current

        yield current
      end
    end

    def all
      @store.all(:sessions)
    end
  end
end
