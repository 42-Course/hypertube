# frozen_string_literal: true

# Loads the shared Ruby domain and state contract used by the web app,
# transcoder API, and workers. Keep this entrypoint focused on stable core
# types so service code can require one file without pulling in runtime jobs.
require_relative "torrent_streaming/domain"
require_relative "torrent_streaming/errors"
require_relative "torrent_streaming/magnet"
require_relative "torrent_streaming/state_store"
require_relative "torrent_streaming/validation"
