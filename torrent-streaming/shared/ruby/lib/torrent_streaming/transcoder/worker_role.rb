# frozen_string_literal: true

# Reads the worker role that decides which boot recovery responsibilities belong
# to this process. The same worker image can run interactive or VOD queues, so
# recovery ownership must come from configuration rather than loaded code.
module TorrentStreaming
  module Transcoder
    module WorkerRole
      INTERACTIVE = "interactive"
      VOD = "vod"

      module_function

      # Returns the configured role exactly as provided by the environment. The
      # predicate methods below interpret the value so unknown roles simply own
      # no boot recovery work.
      def current
        ENV.fetch("TRANSCODER_WORKER_ROLE", "")
      end

      def interactive_recovery_owner?(role: current)
        role == INTERACTIVE
      end

      def vod_recovery_owner?(role: current)
        role == VOD
      end

      def boot_recovery_owner?(role: current)
        interactive_recovery_owner?(role: role)
      end
    end
  end
end
