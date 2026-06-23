# frozen_string_literal: true

# Converts SubRip (.srt) subtitle text into WebVTT, which is what an HTML5
# <track> element can render. OpenSubtitles serves SRT; the browser overlay
# needs VTT. The transform is intentionally minimal: a WEBVTT header, normalized
# newlines, and comma->dot in cue timestamps (the only required syntactic change).
module SrtToVtt
  module_function

  TIMESTAMP = /(\d{2}:\d{2}:\d{2}),(\d{3})/

  def convert(srt)
    body = srt.to_s.dup
    body = body.delete_prefix("﻿")          # strip UTF-8 BOM
    body = body.force_encoding("UTF-8").scrub     # drop invalid bytes
    body = body.gsub("\r\n", "\n").tr("\r", "\n")
    body = body.gsub(TIMESTAMP, '\1.\2')
    "WEBVTT\n\n#{body.strip}\n"
  end
end
