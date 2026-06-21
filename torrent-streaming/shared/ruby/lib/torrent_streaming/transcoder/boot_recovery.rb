# frozen_string_literal: true

# Chooses the boot-time recovery path for the worker process that owns it. The
# interactive worker repairs session/process state, while the VOD worker repairs
# interrupted package attempts, so a single shared hook can run safely in both
# Sidekiq entry points.
require_relative "session_lifecycle"
require_relative "vod_packager"
require_relative "worker_role"

module TorrentStreaming
  module Transcoder
    module BootRecovery
      module_function

      # Runs recovery only for the configured worker role. This keeps
      # interactive session cleanup and VOD packaging recovery from racing each
      # other when the same worker image is started with different queues.
      def run_if_owner(lifecycle: nil, role: WorkerRole.current,
                       vod_packager: nil,
                       skip: ENV["TRANSCODER_SKIP_BOOT_RECOVERY"] == "1")
        return false if skip

        if WorkerRole.interactive_recovery_owner?(role: role)
          (lifecycle || SessionLifecycle.new).recover_stale_sessions!
          return true
        end
        if WorkerRole.vod_recovery_owner?(role: role)
          (vod_packager || VodPackager.new).recover_interrupted!
          return true
        end

        false
      end
    end
  end
end
