# frozen_string_literal: true

# Sidekiq job registry for transcoder execution. The API service owns request
# validation and state orchestration; this wrapper binds queues to worker-side
# probing, interactive ffmpeg lifecycle, cleanup, VOD packaging, and boot recovery.

$LOAD_PATH.unshift(File.expand_path("shared/lib", __dir__))

require "sidekiq"
require "torrent_streaming/transcoder"

redis_url = ENV.fetch("REDIS_URL")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

class InteractiveHealthWorker
  include Sidekiq::Worker
  sidekiq_options queue: :interactive

  def perform
    true
  end
end

class CleanupHealthWorker
  include Sidekiq::Worker
  sidekiq_options queue: :cleanup

  def perform
    true
  end
end

class VodHealthWorker
  include Sidekiq::Worker
  sidekiq_options queue: :vod

  def perform
    true
  end
end

class ProbeMediaJob
  include Sidekiq::Worker
  sidekiq_options queue: :interactive, retry: 1

  # Ignore stale probe jobs when the selected file changed after enqueue; the media
  # JSON record is the durable source of truth, not the queued arguments.
  def perform(media_id, file_index, force = false, complete_file = false)
    safe_file_index = TorrentStreaming::Validation.non_negative_integer!(file_index, field: "file_index")
    media = media_store.find(media_id)
    return media unless media["selected_file_index"] == safe_file_index

    probe = media["metadata_probe"].is_a?(Hash) ? media["metadata_probe"] : {}
    return media if probe["status"] == "ok" && (!complete_file || probe["complete_file"] == true)

    metadata_cache.probe_media!(
      media.fetch("media_id"),
      safe_file_index,
      force: force,
      complete_file: complete_file
    )
  rescue TorrentStreaming::NotFoundError
    nil
  end

  private

  def media_store
    @media_store ||= TorrentStreaming::MediaStore.new(root: File.join(storage_root, "state"))
  end

  def metadata_cache
    @metadata_cache ||= TorrentStreaming::Transcoder::FfprobeMetadataCache.new(storage_root: storage_root)
  end

  def storage_root
    ENV.fetch("STORAGE_ROOT", "/app/storage")
  end
end

class StartInteractiveSessionJob
  include Sidekiq::Worker
  sidekiq_options queue: :interactive, retry: 1

  # Starts the replacement session in the worker process boundary; promotion to
  # active HLS happens only after lifecycle readiness checks pass.
  def perform(session_id, previous_session_id = nil)
    lifecycle.start_session(session_id, previous_session_id)
  end

  private

  def lifecycle
    @lifecycle ||= TorrentStreaming::Transcoder::SessionLifecycle.new
  end
end

class StopSessionJob
  include Sidekiq::Worker
  sidekiq_options queue: :interactive, retry: 1

  # Process termination and artifact deletion are separate side effects: cleanup is
  # queued only after the lifecycle records a fully stopped terminal session.
  def perform(session_id)
    stopped = lifecycle.stop_session(session_id)
    CleanupSessionJob.perform_async(session_id) if stopped&.fetch("state") == "stopped"
    stopped
  end

  private

  def lifecycle
    @lifecycle ||= TorrentStreaming::Transcoder::SessionLifecycle.new
  end
end

class CleanupSessionJob
  include Sidekiq::Worker
  sidekiq_options queue: :cleanup, retry: 1

  def perform(session_id)
    lifecycle.cleanup_session(session_id)
  end

  private

  def lifecycle
    @lifecycle ||= TorrentStreaming::Transcoder::SessionLifecycle.new
  end
end

class CleanupExpiredSessionsJob
  include Sidekiq::Worker
  sidekiq_options queue: :cleanup, retry: 1

  def perform(ttl_seconds = nil)
    kwargs = ttl_seconds.nil? ? {} : { ttl_seconds: ttl_seconds.to_f }
    lifecycle.cleanup_expired_sessions(**kwargs)
  end

  private

  def lifecycle
    @lifecycle ||= TorrentStreaming::Transcoder::SessionLifecycle.new
  end
end

class StartVodPackagingJob
  include Sidekiq::Worker
  sidekiq_options queue: :vod, retry: 1

  # VOD workers publish final HLS from trusted complete-file metadata; they do not
  # participate in interactive session promotion.
  def perform(media_id)
    packager.package(media_id)
  end

  private

  def packager
    @packager ||= TorrentStreaming::Transcoder::VodPackager.new
  end
end

class CancelVodPackagingJob
  include Sidekiq::Worker
  sidekiq_options queue: :vod_control, retry: 1

  # Interactive playback can preempt lower-priority VOD work. The optional attempt
  # id lets lifecycle avoid cancelling a newer packaging attempt.
  def perform(media_id, attempt_id = nil)
    lifecycle.cancel_vod_packaging(media_id, attempt_id: attempt_id, requeue: true)
  end

  private

  def lifecycle
    @lifecycle ||= TorrentStreaming::Transcoder::SessionLifecycle.new
  end
end

begin
  # Boot recovery is role-owned by shared WorkerRole logic so only the interactive
  # or VOD process responsible for a state family repairs it after restart.
  TorrentStreaming::Transcoder::BootRecovery.run_if_owner
rescue StandardError => e
  warn "transcoder boot recovery failed: #{e.class}: #{e.message}"
end
