# frozen_string_literal: true

# Defines the small queue boundary shared by API code, worker lifecycle code,
# and tests. Durable state is written before callers enqueue work; this wrapper
# only turns an already-decided job into the Sidekiq client payload or a test
# adapter call.
module TorrentStreaming
  module Transcoder
    module JobClient
      class << self
        attr_accessor :adapter
      end

      module_function

      # Enqueues a job without hiding which queue owns it. The explicit queue
      # argument matters because interactive, cleanup, VOD, and VOD-control work
      # have different recovery and priority contracts.
      def enqueue(job_class, args:, queue:)
        if JobClient.adapter
          return JobClient.adapter.call(job_class: job_class, args: args, queue: queue.to_s)
        end

        require "sidekiq"

        configure_sidekiq_client
        Sidekiq::Client.push(
          "class" => job_class,
          "queue" => queue.to_s,
          "args" => args
        )
      end

      def configure_sidekiq_client
        return if defined?(@sidekiq_configured) && @sidekiq_configured

        Sidekiq.configure_client do |config|
          config.redis = { url: ENV.fetch("REDIS_URL") }
        end
        @sidekiq_configured = true
      end
      private_class_method :configure_sidekiq_client
    end
  end
end
