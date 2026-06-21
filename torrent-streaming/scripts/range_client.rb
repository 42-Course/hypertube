#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual range-server API client for adding a magnet, waiting for metadata,
# selecting a playable video, and printing the direct /files URL for VLC.

require "json"
require "net/http"
require "optparse"
require "uri"

$LOAD_PATH.unshift(File.expand_path("../shared/ruby/lib", __dir__))

require "torrent_streaming/magnet"

module RangeClient
  DEFAULT_PORT = ENV.fetch("RANGE_SERVER_PORT", "7000")
  DEFAULT_BASE_URL = ENV.fetch("RANGE_SERVER_URL", "http://localhost:#{DEFAULT_PORT}")
  DEFAULT_METADATA_TIMEOUT_SECONDS = Integer(ENV.fetch("RANGE_CLIENT_METADATA_TIMEOUT_SECONDS", "600"))
  DEFAULT_POLL_SECONDS = Float(ENV.fetch("RANGE_CLIENT_POLL_SECONDS", "5"))
  DEFAULT_HTTP_TIMEOUT_SECONDS = Integer(ENV.fetch("RANGE_CLIENT_HTTP_TIMEOUT_SECONDS", "30"))

  class Error < StandardError; end

  class HttpError < Error
    attr_reader :status, :payload

    def initialize(status, payload)
      @status = status
      @payload = payload
      detail = payload.is_a?(Hash) ? (payload["message"] || payload["error"]) : nil
      super(["HTTP #{status}", detail].compact.join(": "))
    end
  end

  module_function

  def media_id(magnet)
    TorrentStreaming::Magnet.media_id(magnet)
  end

  def torrent_payload(magnet)
    { "media_id" => media_id(magnet), "magnet" => TorrentStreaming::Magnet.normalize(magnet) }
  end

  def supported_videos(files_payload)
    Array(files_payload.fetch("files", [])).select do |file|
      file["kind"] == "video" && file["supported"] != false
    end.sort_by { |file| Integer(file.fetch("index")) }
  end

  def first_supported_video_index(files_payload)
    supported_videos(files_payload).first&.fetch("index")
  end

  def vlc_url(base_url:, media_id:, file_index:)
    "#{normalize_base_url(base_url)}/files/#{media_id}/#{file_index}"
  end

  def normalize_base_url(base_url)
    base_url.to_s.sub(%r{/+\z}, "")
  end

  def human_bytes(value)
    bytes = Integer(value || 0)
    units = %w[B KiB MiB GiB TiB]
    amount = bytes.to_f
    unit = units.first
    units.each do |candidate|
      unit = candidate
      break if amount < 1024.0 || candidate == units.last

      amount /= 1024.0
    end
    unit == "B" ? "#{bytes} B" : format("%.1f %s", amount, unit)
  rescue ArgumentError, TypeError
    "unknown"
  end

  # Formats progress diagnostics from range-server polling so manual runs show
  # whether discovery, cache mode, or tracker/DHT alerts explain a slow magnet.
  def metadata_wait_message(status, torrent_status, elapsed)
    diagnostics = status["diagnostics"] || {}
    parts = [
      "Metadata not ready yet",
      "status=#{torrent_status}",
      "elapsed=#{elapsed}s",
      "peers=#{diagnostics.fetch("num_peers", "?")}",
      "seeds=#{diagnostics.fetch("num_seeds", "?")}",
      "candidates=#{diagnostics.fetch("connect_candidates", "?")}"
    ]
    parts << "profile=#{diagnostics["discovery_profile"]}" if diagnostics["discovery_profile"]
    parts << "cache=#{diagnostics["cache_mode"]}" if diagnostics["cache_mode"]
    alert_summary = diagnostics["alert_summary"] || {}
    if alert_summary.any?
      parts << "tracker_alerts=#{alert_summary.fetch("tracker_alerts", "?")}"
      parts << "tracker_errors=#{alert_summary.fetch("tracker_errors", "?")}"
      parts << "dht_alerts=#{alert_summary.fetch("dht_alerts", "?")}"
    end
    alerts = Array(diagnostics["recent_alerts"])
    if (alert = alerts.last)
      parts << "last_alert_at=#{alert["at"]}" if alert["at"]
      parts << "last_alert=#{alert["type"]}: #{alert["message"]}"
    end
    "#{parts.join(", ")}; retrying..."
  end

  # Small injectable transport used by the CLI and tests; all user-facing API
  # sequencing stays in App so fakes can assert the exact range-server calls.
  class JsonTransport
    def initialize(base_url:, timeout_seconds: DEFAULT_HTTP_TIMEOUT_SECONDS)
      @base_url = RangeClient.normalize_base_url(base_url)
      @timeout_seconds = timeout_seconds
    end

    def get_json(path)
      request_json("GET", path)
    end

    def post_json(path, payload)
      request_json("POST", path, payload)
    end

    private

    def request_json(method, path, payload = nil)
      uri = URI.join("#{@base_url}/", path.sub(%r{\A/+}, ""))
      request = method == "POST" ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      if payload
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)
      end

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: @timeout_seconds,
        read_timeout: @timeout_seconds
      ) { |http| http.request(request) }

      parsed = parse_response(response)
      raise HttpError.new(response.code.to_i, parsed) unless response.code.to_i.between?(200, 299)

      parsed
    end

    def parse_response(response)
      body = response.body.to_s
      return {} if body.empty?

      JSON.parse(body)
    rescue JSON::ParserError => e
      raise Error, "invalid JSON response from range-server: #{e.message}"
    end
  end

  class App
    def initialize(
      base_url: DEFAULT_BASE_URL,
      transport: JsonTransport.new(base_url: base_url),
      input: $stdin,
      output: $stdout,
      metadata_timeout_seconds: DEFAULT_METADATA_TIMEOUT_SECONDS,
      poll_seconds: DEFAULT_POLL_SECONDS,
      sleeper: ->(seconds) { sleep(seconds) },
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    )
      @base_url = RangeClient.normalize_base_url(base_url)
      @transport = transport
      @input = input
      @output = output
      @metadata_timeout_seconds = metadata_timeout_seconds
      @poll_seconds = poll_seconds
      @sleeper = sleeper
      @clock = clock
      @output.sync = true if @output.respond_to?(:sync=)
    end

    # Mirrors the manual range-server workflow: create torrent, poll metadata,
    # list videos, select one, then emit the seekable file endpoint.
    def run(magnet = nil, file_index: nil)
      magnet = prompt_magnet if magnet.to_s.strip.empty?
      payload = RangeClient.torrent_payload(magnet)
      media_id = payload.fetch("media_id")

      @output.puts "Range-server: #{@base_url}"
      @output.puts "Media ID: #{media_id}"
      @output.puts "Adding torrent..."

      @transport.post_json("/torrents", payload)
      @output.puts "Waiting for torrent metadata (timeout=#{@metadata_timeout_seconds}s)..."
      wait_for_metadata(media_id)
      @output.puts "Metadata ready."

      @output.puts "Fetching file list..."
      files_payload = @transport.get_json("/torrents/#{media_id}/files")
      videos = RangeClient.supported_videos(files_payload)
      raise Error, "no supported video file found" if videos.empty?

      print_videos(videos)
      selected_index = file_index.nil? ? choose_file_index(videos) : Integer(file_index)
      unless videos.any? { |file| Integer(file.fetch("index")) == selected_index }
        raise Error, "file_index #{selected_index} is not a supported video"
      end

      @output.puts "Selecting file #{selected_index}..."
      @transport.post_json("/torrents/#{media_id}/select-file", { "file_index" => selected_index })
      url = RangeClient.vlc_url(base_url: @base_url, media_id: media_id, file_index: selected_index)

      @output.puts
      @output.puts "VLC URL:"
      @output.puts url
      url
    end

    private

    def prompt_magnet
      @output.print "Magnet: "
      @output.flush if @output.respond_to?(:flush)
      value = @input.gets&.strip
      raise Error, "magnet is required" if value.to_s.empty?

      value
    end

    def wait_for_metadata(media_id)
      started_at = @clock.call
      deadline = started_at + @metadata_timeout_seconds
      loop do
        status = @transport.get_json("/torrents/#{media_id}")
        return status if status["metadata_ready"] == true

        torrent_status = status["status"] || "unknown"
        raise Error, "torrent failed: #{status["error"]}" if torrent_status == "failed"

        remaining = deadline - @clock.call
        raise Error, "metadata timeout after #{@metadata_timeout_seconds}s" if remaining <= 0

        elapsed = (@clock.call - started_at).round
        @output.puts metadata_wait_message(status, torrent_status, elapsed)
        @sleeper.call([@poll_seconds, remaining].min)
      end
    end

    def metadata_wait_message(status, torrent_status, elapsed)
      RangeClient.metadata_wait_message(status, torrent_status, elapsed)
    end

    def print_videos(videos)
      @output.puts
      @output.puts "Supported video files:"
      videos.each do |file|
        index = file.fetch("index")
        name = file["display_name"] || file["path"] || "file #{index}"
        size = RangeClient.human_bytes(file["size"])
        @output.puts "  [#{index}] #{name} (#{size})"
      end
    end

    def choose_file_index(videos)
      default = Integer(videos.first.fetch("index"))
      @output.print "File index [#{default}]: "
      @output.flush if @output.respond_to?(:flush)
      answer = @input.gets&.strip
      return default if answer.to_s.empty?

      Integer(answer)
    rescue ArgumentError
      raise Error, "file_index must be an integer"
    end
  end

  class << self
    def parse_args(argv)
      options = {
        base_url: DEFAULT_BASE_URL,
        metadata_timeout_seconds: DEFAULT_METADATA_TIMEOUT_SECONDS,
        poll_seconds: DEFAULT_POLL_SECONDS,
        file_index: nil
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: ruby scripts/range_client.rb [options] [magnet]"
        opts.on("--url URL", "Range-server base URL") { |value| options[:base_url] = value }
        opts.on("--timeout SECONDS", Integer, "Metadata timeout") do |value|
          options[:metadata_timeout_seconds] = value
        end
        opts.on("--poll SECONDS", Float, "Metadata polling interval") { |value| options[:poll_seconds] = value }
        opts.on("--file-index INDEX", Integer, "Select a video file without prompting") do |value|
          options[:file_index] = value
        end
      end

      parser.parse!(argv)
      raise Error, "too many arguments" if argv.length > 1

      [options, argv.first]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options, magnet = RangeClient.parse_args(ARGV)
    app = RangeClient::App.new(
      base_url: options.fetch(:base_url),
      metadata_timeout_seconds: options.fetch(:metadata_timeout_seconds),
      poll_seconds: options.fetch(:poll_seconds)
    )
    app.run(magnet, file_index: options[:file_index])
  rescue TorrentStreaming::InvalidMagnetError, RangeClient::Error, OptionParser::ParseError => e
    warn "range_client: #{e.message}"
    exit 1
  end
end
