#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual cold-start probe for measuring metadata discovery when cache reuse is
# disabled. It shares the range client transport but fails if the target misses
# the configured metadata-time budget.

require "optparse"

require_relative "range_client"

module RangeColdStartProbe
  DEFAULT_TARGET_SECONDS = Integer(ENV.fetch("RANGE_COLD_START_TARGET_SECONDS", "30"))
  DEFAULT_TIMEOUT_SECONDS = Integer(ENV.fetch("RANGE_COLD_START_TIMEOUT_SECONDS", DEFAULT_TARGET_SECONDS.to_s))
  DEFAULT_POLL_SECONDS = Float(ENV.fetch("RANGE_COLD_START_POLL_SECONDS", "1"))

  class Error < StandardError; end

  module_function

  # Cold-start measurements are only meaningful when the range server has been
  # started with cache writes and fastresume reuse disabled.
  def cache_off_requested?(env = ENV)
    env.fetch("RANGE_SERVER_CACHE_MODE", "").strip.downcase == "off"
  end

  def metadata_elapsed_seconds(started_at:, finished_at:)
    (finished_at - started_at).round(3)
  end

  class Probe
    def initialize(
      base_url: RangeClient::DEFAULT_BASE_URL,
      transport: RangeClient::JsonTransport.new(base_url: base_url),
      output: $stdout,
      timeout_seconds: DEFAULT_TIMEOUT_SECONDS,
      target_seconds: DEFAULT_TARGET_SECONDS,
      poll_seconds: DEFAULT_POLL_SECONDS,
      sleeper: ->(seconds) { sleep(seconds) },
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    )
      @base_url = RangeClient.normalize_base_url(base_url)
      @transport = transport
      @output = output
      @timeout_seconds = timeout_seconds
      @target_seconds = target_seconds
      @poll_seconds = poll_seconds
      @sleeper = sleeper
      @clock = clock
      @output.sync = true if @output.respond_to?(:sync=)
    end

    # The timeout bounds the whole probe; the target is the stricter service
    # objective that turns a successful-but-slow metadata lookup into failure.
    def run(magnet)
      raise Error, "magnet is required" if magnet.to_s.strip.empty?

      payload = RangeClient.torrent_payload(magnet)
      media_id = payload.fetch("media_id")

      @output.puts "Range-server: #{@base_url}"
      @output.puts "Media ID: #{media_id}"
      @output.puts "Cold-start cache mode requested: off"
      @output.puts "Target metadata time: #{@target_seconds}s"
      @output.puts "Adding torrent..."

      started_at = @clock.call
      @transport.post_json("/torrents", payload)
      status = wait_for_metadata(media_id, started_at)
      elapsed = RangeColdStartProbe.metadata_elapsed_seconds(started_at: started_at, finished_at: @clock.call)

      @output.puts "Metadata ready in #{format("%.3f", elapsed)}s."
      if elapsed > @target_seconds
        raise Error, "metadata exceeded target #{@target_seconds}s (elapsed=#{format("%.3f", elapsed)}s)"
      end

      status
    end

    private

    def wait_for_metadata(media_id, started_at)
      deadline = started_at + @timeout_seconds
      loop do
        status = @transport.get_json("/torrents/#{media_id}")
        return status if status["metadata_ready"] == true

        torrent_status = status["status"] || "unknown"
        raise Error, "torrent failed: #{status["error"]}" if torrent_status == "failed"

        now = @clock.call
        remaining = deadline - now
        raise Error, "metadata timeout after #{@timeout_seconds}s" if remaining <= 0

        elapsed = (now - started_at).round
        @output.puts RangeClient.metadata_wait_message(status, torrent_status, elapsed)
        @sleeper.call([@poll_seconds, remaining].min)
      end
    end
  end

  class << self
    def parse_args(argv)
      options = {
        base_url: RangeClient::DEFAULT_BASE_URL,
        timeout_seconds: DEFAULT_TIMEOUT_SECONDS,
        target_seconds: DEFAULT_TARGET_SECONDS,
        poll_seconds: DEFAULT_POLL_SECONDS
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: RANGE_SERVER_CACHE_MODE=off ruby scripts/range_cold_start_probe.rb [options] [magnet]"
        opts.on("--url URL", "Range-server base URL") { |value| options[:base_url] = value }
        opts.on("--timeout SECONDS", Integer, "Metadata timeout") { |value| options[:timeout_seconds] = value }
        opts.on("--target SECONDS", Integer, "Expected metadata target") { |value| options[:target_seconds] = value }
        opts.on("--poll SECONDS", Float, "Metadata polling interval") { |value| options[:poll_seconds] = value }
      end

      parser.parse!(argv)
      raise Error, "too many arguments" if argv.length > 1

      [options, argv.first || ENV["RANGE_COLD_START_MAGNET"]]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    raise RangeColdStartProbe::Error, "set RANGE_SERVER_CACHE_MODE=off before running a cold-start probe" unless RangeColdStartProbe.cache_off_requested?

    options, magnet = RangeColdStartProbe.parse_args(ARGV)
    probe = RangeColdStartProbe::Probe.new(
      base_url: options.fetch(:base_url),
      timeout_seconds: options.fetch(:timeout_seconds),
      target_seconds: options.fetch(:target_seconds),
      poll_seconds: options.fetch(:poll_seconds)
    )
    probe.run(magnet)
  rescue TorrentStreaming::InvalidMagnetError, RangeClient::Error, RangeColdStartProbe::Error, OptionParser::ParseError => e
    warn "range_cold_start_probe: #{e.message}"
    exit 1
  end
end
