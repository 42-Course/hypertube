# frozen_string_literal: true

# Loads the shared transcoder orchestration surface used by the API and worker
# services. Keeping these requires together gives both runtimes the same session
# lifecycle, command construction, queue, recovery, and packaging contracts.
require_relative "transcoder/boot_recovery"
require_relative "transcoder/ffmpeg_command_builder"
require_relative "transcoder/ffprobe_metadata_cache"
require_relative "transcoder/job_client"
require_relative "transcoder/session_lifecycle"
require_relative "transcoder/session_manager"
require_relative "transcoder/subtitle_sidecar_writer"
require_relative "transcoder/vod_packager"
require_relative "transcoder/worker_role"
