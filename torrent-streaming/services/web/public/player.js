/*
 * Browser player controller for the torrent streaming UI.
 * It consumes the server's media/session payload contract, attaches playable HLS, and keeps the custom global timeline in sync with short-lived transcoder sessions.
 */

(function(globalObject) {
  "use strict";

  var DEBUG_PREFIX = "[torrent-streaming-player]";

  function consoleLogger(methodName) {
    var consoleObject = globalObject.console;
    if (!consoleObject || typeof consoleObject[methodName] !== "function") {
      return null;
    }
    return consoleObject[methodName].bind(consoleObject);
  }

  function logDebug(message, details) {
    var logger = consoleLogger("log");
    if (!logger) {
      return;
    }
    if (details === undefined) {
      logger(DEBUG_PREFIX + " " + message);
    } else {
      logger(DEBUG_PREFIX + " " + message, details);
    }
  }

  function logError(message, details) {
    var logger = consoleLogger("error") || consoleLogger("log");
    if (!logger) {
      return;
    }
    if (details === undefined) {
      logger(DEBUG_PREFIX + " " + message);
    } else {
      logger(DEBUG_PREFIX + " " + message, details);
    }
  }

  function summarizeError(error) {
    if (!error) {
      return null;
    }
    return {
      name: error.name || "Error",
      message: error.message || String(error),
      payload: error.payload || null,
      stack: error.stack || null
    };
  }

  function summarizeVideoError(videoError) {
    if (!videoError) {
      return null;
    }
    return {
      code: videoError.code,
      message: videoError.message || null
    };
  }

  function summarizeVideo(video) {
    if (!video) {
      return null;
    }
    return {
      src: typeof video.getAttribute === "function" ? video.getAttribute("src") : video.src || "",
      currentSrc: video.currentSrc || "",
      readyState: video.readyState,
      networkState: video.networkState,
      currentTime: video.currentTime || 0,
      paused: video.paused,
      ended: video.ended,
      error: summarizeVideoError(video.error)
    };
  }

  function videoHasPlayableSource(video) {
    if (!video) {
      return false;
    }
    var attributeSource = typeof video.getAttribute === "function" ? video.getAttribute("src") : video.src || "";
    return Boolean(attributeSource || video.currentSrc);
  }

  function setVideoControlsEnabled(video, enabled) {
    if (!video) {
      return;
    }
    if (enabled) {
      if (typeof video.setAttribute === "function") {
        video.setAttribute("controls", "controls");
      } else {
        video.controls = true;
      }
    } else if (typeof video.removeAttribute === "function") {
      video.removeAttribute("controls");
    } else {
      video.controls = false;
    }
  }

  function hlsSupportSummary(video) {
    var nativeCanPlayType = "";
    var hlsJsSupported = false;
    if (video && typeof video.canPlayType === "function") {
      nativeCanPlayType = video.canPlayType("application/vnd.apple.mpegurl") || "";
    }
    if (globalObject.Hls && typeof globalObject.Hls.isSupported === "function") {
      try {
        hlsJsSupported = Boolean(globalObject.Hls.isSupported());
      } catch (error) {
        logError("hls.js support probe failed", summarizeError(error));
      }
    }
    return {
      nativeCanPlayType: nativeCanPlayType,
      nativeHls: Boolean(nativeCanPlayType),
      hlsJsAvailable: Boolean(globalObject.Hls),
      hlsJsSupported: hlsJsSupported
    };
  }

  function summarizeMediaStatus(payload) {
    if (!payload || typeof payload !== "object") {
      return null;
    }
    var playback = payload.playback || {};
    var metadataProbe = payload.metadata_probe || {};
    var progress = payload.video_progress || {};
    return {
      state: payload.state,
      info_hash: payload.info_hash,
      selected_file_index: payload.selected_file_index,
      duration_seconds: payload.duration_seconds,
      current_session_id: payload.current_session_id,
      active_session_id: payload.active_session_id,
      pending_session_id: payload.pending_session_id,
      playback: {
        active_session_id: playback.active_session_id,
        playlist_url: playback.playlist_url,
        subtitle_url: playback.subtitle_url,
        subtitle_mode: playback.subtitle_mode || "none",
        session_start_time_seconds: playback.session_start_time_seconds,
        selected_audio: playback.selected_audio,
        selected_subtitle: playback.selected_subtitle
      },
      metadata_probe: {
        status: metadataProbe.status,
        error: metadataProbe.error,
        duration_seconds: metadataProbe.duration_seconds
      },
      video_progress: {
        bytes_downloaded: progress.bytes_downloaded,
        bytes_total: progress.bytes_total
      },
      warnings: payload.warnings || [],
      errors: payload.errors || []
    };
  }

  function summarizePlaybackStatus(payload) {
    if (!payload || typeof payload !== "object") {
      return null;
    }
    return {
      session_id: payload.session_id,
      state: payload.state,
      media_id: payload.media_id,
      playlist_url: payload.playlist_url,
      subtitle_url: payload.subtitle_url,
      subtitle_mode: payload.subtitle_mode || "none",
      error: payload.error,
      session_start_time_seconds: payload.session_start_time_seconds,
      selected_audio: payload.selected_audio,
      selected_subtitle: payload.selected_subtitle
    };
  }

  function debugSignature(value) {
    try {
      return JSON.stringify(value);
    } catch (_error) {
      return "";
    }
  }

  function requestVideoPlay(video, context) {
    try {
      var playPromise = video.play();
      if (playPromise && typeof playPromise.then === "function") {
        playPromise.then(function() {
          logDebug("video.play resolved", {
            context: context,
            video: summarizeVideo(video)
          });
        }).catch(function(error) {
          logError("video.play rejected", {
            context: context,
            error: summarizeError(error),
            video: summarizeVideo(video)
          });
        });
      } else if (playPromise && typeof playPromise.catch === "function") {
        playPromise.catch(function(error) {
          logError("video.play rejected", {
            context: context,
            error: summarizeError(error),
            video: summarizeVideo(video)
          });
        });
      }
    } catch (error) {
      logError("video.play threw", {
        context: context,
        error: summarizeError(error),
        video: summarizeVideo(video)
      });
    }
  }

  function isFiniteNumber(value) {
    return typeof value === "number" && Number.isFinite(value);
  }

  function clampTargetSeconds(targetSeconds, durationSeconds) {
    var value = Number(targetSeconds);
    if (!Number.isFinite(value) || value < 0) {
      value = 0;
    }
    if (isFiniteNumber(durationSeconds)) {
      value = Math.min(value, durationSeconds);
    }
    return value;
  }

  function formatClock(totalSeconds) {
    if (!Number.isFinite(totalSeconds) || totalSeconds < 0) {
      return "0:00";
    }
    var seconds = Math.floor(totalSeconds);
    var hours = Math.floor(seconds / 3600);
    var minutes = Math.floor((seconds % 3600) / 60);
    var remainder = seconds % 60;
    if (hours > 0) {
      return String(hours) + ":" + String(minutes).padStart(2, "0") + ":" + String(remainder).padStart(2, "0");
    }
    return String(minutes) + ":" + String(remainder).padStart(2, "0");
  }

  function deriveTimelineState(input) {
    var durationSeconds = input.durationSeconds;
    var globalCurrentTime = Math.max(0, Number(input.globalCurrentTime || 0));
    var seekEnabled = isFiniteNumber(durationSeconds);
    var max = seekEnabled ? Math.max(0, durationSeconds) : Math.max(1, globalCurrentTime);
    var value = seekEnabled ? clampTargetSeconds(globalCurrentTime, durationSeconds) : Math.min(max, globalCurrentTime);

    return {
      seekEnabled: seekEnabled,
      min: 0,
      max: max,
      value: value,
      currentLabel: formatClock(globalCurrentTime),
      totalLabel: seekEnabled ? formatClock(durationSeconds) : "Unknown duration"
    };
  }

  function currentSessionIdFromStatus(mediaStatus) {
    if (!mediaStatus || typeof mediaStatus !== "object") {
      return null;
    }
    return mediaStatus.pending_session_id || mediaStatus.active_session_id || null;
  }

  // Guards session polling against stale responses from sessions superseded by a later seek.
  function shouldApplySessionStatus(expectedSessionId, payload) {
    return Boolean(
      expectedSessionId &&
      payload &&
      typeof payload === "object" &&
      payload.session_id === expectedSessionId
    );
  }

  // Accepts a playlist only when it belongs to the session the UI is currently waiting for.
  function shouldLoadPlaylist(desiredSessionId, playlistPayload) {
    if (!playlistPayload || typeof playlistPayload !== "object" || !playlistPayload.session_id) {
      return false;
    }
    if (!desiredSessionId) {
      return true;
    }
    return playlistPayload.session_id === desiredSessionId;
  }

  // Tracks the server-rendered portions of the page so polling can trigger a reload when controls change.
  function mediaStructureSignature(mediaStatus) {
    if (!mediaStatus || typeof mediaStatus !== "object") {
      return "";
    }
    return JSON.stringify({
      selectedFileIndex: mediaStatus.selected_file_index,
      files: (mediaStatus.files || []).map(function(file) {
        return [file.index, file.display_name, file.kind, file.supported, file.selected];
      }),
      audioTracks: (mediaStatus.audio_tracks || []).map(function(track) {
        return [track.index, track.label, track.supported];
      }),
      subtitles: (mediaStatus.subtitles || []).map(function(track) {
        return [track.index, track.label, track.supported, track.reason];
      })
    });
  }

  function shouldRefreshMediaPage(previousStatus, nextStatus) {
    if (!previousStatus || !nextStatus) {
      return false;
    }
    return mediaStructureSignature(previousStatus) !== mediaStructureSignature(nextStatus);
  }

  // Converts the server-rendered media payload into the smaller playlist contract used by attachPlaylist.
  function bootstrapPlaylistPayload(mediaStatus) {
    if (!mediaStatus || !mediaStatus.playback || !mediaStatus.playback.playlist_url) {
      return null;
    }
    return {
      session_id: mediaStatus.playback.active_session_id,
      playlist_url: mediaStatus.playback.playlist_url,
      subtitle_url: mediaStatus.playback.subtitle_url,
      subtitle_mode: mediaStatus.playback.subtitle_mode || "none",
      session_start_time_seconds: mediaStatus.playback.session_start_time_seconds || 0
    };
  }

  function stopTargetSessionId(currentPlaylistSessionId, activeSessionId, desiredSessionId) {
    return currentPlaylistSessionId || activeSessionId || desiredSessionId || null;
  }

  // Replaces the browser text track for sidecar subtitles when a new session playlist is attached.
  function syncSubtitleTrack(video, subtitleUrl) {
    var existing = Array.prototype.slice.call(video.querySelectorAll("track[data-session-subtitle]"));
    existing.forEach(function(track) {
      track.remove();
    });

    if (!subtitleUrl) {
      return null;
    }

    var doc = video.ownerDocument || document;
    var track = doc.createElement("track");
    track.kind = "subtitles";
    track.label = "Selected subtitle";
    track.srclang = "und";
    track.src = subtitleUrl;
    track.default = true;
    track.setAttribute("data-session-subtitle", "true");
    video.appendChild(track);
    if (track.track) {
      track.track.mode = "showing";
    }
    return track;
  }

  function activateFirstHlsSubtitle(hls) {
    if (!hls || !Array.isArray(hls.subtitleTracks) || hls.subtitleTracks.length === 0) {
      return false;
    }
    hls.subtitleDisplay = true;
    hls.subtitleTrack = 0;
    return true;
  }

  function postJson(url, payload) {
    logDebug("POST request", { url: url, payload: payload || {} });
    return fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload || {})
    }).then(function(response) {
      return response.json().then(function(data) {
        if (!response.ok) {
          logError("POST failed", {
            url: url,
            status: response.status,
            payload: data
          });
          var error = new Error(data && data.message ? data.message : "Request failed");
          error.payload = data;
          throw error;
        }
        logDebug("POST succeeded", {
          url: url,
          status: response.status,
          payload: data
        });
        return data;
      });
    }).catch(function(error) {
      logError("POST exception", {
        url: url,
        error: summarizeError(error)
      });
      throw error;
    });
  }

  function getJson(url) {
    return fetch(url, {
      headers: { "Accept": "application/json" }
    }).then(function(response) {
      return response.json().then(function(data) {
        if (!response.ok) {
          logError("GET failed", {
            url: url,
            status: response.status,
            payload: data
          });
          var error = new Error(data && data.message ? data.message : "Request failed");
          error.payload = data;
          throw error;
        }
        return data;
      });
    }).catch(function(error) {
      logError("GET exception", {
        url: url,
        error: summarizeError(error)
      });
      throw error;
    });
  }

  function selectValue(select) {
    if (!select) {
      return null;
    }
    return select.value === "" ? null : Number(select.value);
  }

  function setSelectValue(select, value) {
    if (!select) {
      return;
    }
    var selectedValue = value === null || value === undefined ? "" : String(value);
    select.value = selectedValue;
  }

  // Coordinates polling, user commands, and HLS attachment for a single media page.
  function PlayerController(root, bootstrap) {
    this.root = root;
    this.mediaId = bootstrap.media_id;
    this.mediaStatus = bootstrap;
    this.desiredSessionId = currentSessionIdFromStatus(bootstrap);
    this.activeSessionId = bootstrap.active_session_id || null;
    this.currentPlaylistSessionId = bootstrap.playback && bootstrap.playback.active_session_id || null;
    this.runtimeState = "idle";
    this.seekTimer = null;
    this.timelineDragging = false;
    this.trackChangeInFlight = false;
    this.hls = null;
    this.playlistAttached = Boolean(bootstrapPlaylistPayload(bootstrap));
    this.lastMediaDebugSignature = "";
    this.lastPlaybackDebugSignature = "";
    var doc = root.ownerDocument || globalObject.document;
    this.dom = {
      video: root.querySelector("[data-player-video]"),
      message: root.querySelector("[data-player-message]"),
      playButton: root.querySelector("[data-play-button]"),
      stopButton: root.querySelector("[data-stop-button]"),
      timeline: root.querySelector("[data-timeline]"),
      timelineCurrent: root.querySelector("[data-timeline-current]"),
      timelineTotal: root.querySelector("[data-timeline-total]"),
      runtimeState: root.querySelector("[data-runtime-state]"),
      audioSelect: root.querySelector("[data-audio-select]"),
      subtitleSelect: root.querySelector("[data-subtitle-select]"),
      statusState: doc ? doc.querySelector("[data-status-state]") : null,
      statusInfoHash: doc ? doc.querySelector("[data-status-info-hash]") : null,
      statusDownloaded: doc ? doc.querySelector("[data-status-downloaded]") : null,
      statusTotal: doc ? doc.querySelector("[data-status-total]") : null,
      statusDuration: doc ? doc.querySelector("[data-status-duration]") : null,
      statusSession: doc ? doc.querySelector("[data-status-session]") : null
    };
  }

  PlayerController.prototype.init = function() {
    var self = this;
    logDebug("controller init", {
      media_id: this.mediaId,
      bootstrap: summarizeMediaStatus(this.mediaStatus),
      hls_support: hlsSupportSummary(this.dom.video)
    });
    setVideoControlsEnabled(this.dom.video, this.playlistAttached);
    this.installVideoDebugListeners();
    this.installEmptyPlaybackGuard();
    this.dom.playButton.addEventListener("click", function() {
      self.startPlayback();
    });
    this.dom.stopButton.addEventListener("click", function() {
      self.stopPlayback();
    });
    this.dom.timeline.addEventListener("input", function() {
      self.timelineDragging = true;
      self.renderTimeline(Number(self.dom.timeline.value));
    });
    this.dom.timeline.addEventListener("change", function() {
      var targetSeconds = Number(self.dom.timeline.value);
      self.timelineDragging = false;
      self.scheduleSeek(targetSeconds);
    });
    this.dom.video.addEventListener("timeupdate", function() {
      self.renderTimeline();
    });
    this.dom.audioSelect.addEventListener("change", function() {
      self.changeTrackSelection();
    });
    this.dom.subtitleSelect.addEventListener("change", function() {
      self.changeTrackSelection();
    });
    this.attachBootstrapPlaylist();
    this.renderFromMediaStatus(this.mediaStatus);
    this.pollMedia();
    this.pollPlayback();
  };

  PlayerController.prototype.installVideoDebugListeners = function() {
    var video = this.dom.video;
    if (!video || typeof video.addEventListener !== "function") {
      return;
    }

    [
      "loadstart",
      "loadedmetadata",
      "loadeddata",
      "canplay",
      "playing",
      "waiting",
      "stalled",
      "suspend",
      "emptied",
      "ended",
      "pause",
      "seeking",
      "seeked",
      "abort"
    ].forEach(function(eventName) {
      video.addEventListener(eventName, function() {
        logDebug("video event: " + eventName, summarizeVideo(video));
      });
    });
    video.addEventListener("error", function() {
      logError("video event: error", summarizeVideo(video));
    });
  };

  PlayerController.prototype.installEmptyPlaybackGuard = function() {
    var self = this;
    var video = this.dom.video;
    if (!video || typeof video.addEventListener !== "function") {
      return;
    }

    video.addEventListener("play", function(event) {
      if (self.playlistAttached || videoHasPlayableSource(video)) {
        return;
      }
      if (event && typeof event.preventDefault === "function") {
        event.preventDefault();
      }
      if (typeof video.pause === "function") {
        video.pause();
      }
      logDebug("empty video playback blocked", {
        desired_session_id: self.desiredSessionId,
        active_session_id: self.activeSessionId,
        video: summarizeVideo(video)
      });
      self.setMessage("Use Play to start a playback session.", "info");
    });
  };

  PlayerController.prototype.setMessage = function(text, kind) {
    this.dom.message.textContent = text;
    this.dom.message.className = "banner banner--" + (kind || "info");
  };

  PlayerController.prototype.setRuntimeState = function(state) {
    this.runtimeState = state;
    this.dom.runtimeState.textContent = state;
  };

  // HLS sessions start at zero after each seek, so the UI timeline adds the session start offset.
  PlayerController.prototype.currentGlobalTime = function() {
    var playbackStart = this.mediaStatus.playback && this.mediaStatus.playback.session_start_time_seconds || 0;
    return playbackStart + (this.dom.video.currentTime || 0);
  };

  PlayerController.prototype.renderTimeline = function(globalTimeOverride) {
    var current = isFiniteNumber(globalTimeOverride) ? globalTimeOverride : this.currentGlobalTime();
    var timelineState = deriveTimelineState({
      durationSeconds: this.mediaStatus.duration_seconds,
      globalCurrentTime: current
    });
    this.dom.timeline.min = String(timelineState.min);
    this.dom.timeline.max = String(timelineState.max);
    if (!this.timelineDragging || isFiniteNumber(globalTimeOverride)) {
      this.dom.timeline.value = String(timelineState.value);
    }
    this.dom.timeline.disabled = !timelineState.seekEnabled;
    this.dom.timelineCurrent.textContent = timelineState.currentLabel;
    this.dom.timelineTotal.textContent = timelineState.totalLabel;
  };

  // Applies the media payload contract from the server. Server-rendered controls
  // are refreshed with a full reload only when files or tracks changed shape.
  PlayerController.prototype.renderFromMediaStatus = function(payload) {
    if (shouldRefreshMediaPage(this.mediaStatus, payload) && globalObject.location && globalObject.location.reload) {
      logDebug("media structure changed; reloading page", {
        previous: summarizeMediaStatus(this.mediaStatus),
        next: summarizeMediaStatus(payload)
      });
      globalObject.location.reload();
      return;
    }
    var mediaSummary = summarizeMediaStatus(payload);
    var mediaSignature = debugSignature(mediaSummary);
    if (mediaSignature !== this.lastMediaDebugSignature) {
      logDebug("media status changed", mediaSummary);
      this.lastMediaDebugSignature = mediaSignature;
      if (Array.isArray(payload.errors) && payload.errors.length > 0) {
        logError("media status reports errors", {
          errors: payload.errors,
          metadata_probe: mediaSummary.metadata_probe,
          state: mediaSummary.state,
          current_session_id: mediaSummary.current_session_id,
          active_session_id: mediaSummary.active_session_id,
          pending_session_id: mediaSummary.pending_session_id
        });
      }
      if (Array.isArray(payload.warnings) && payload.warnings.length > 0) {
        logDebug("media status reports warnings", {
          warnings: payload.warnings,
          metadata_probe: mediaSummary.metadata_probe,
          state: mediaSummary.state
        });
      }
    }
    this.mediaStatus = payload;
    this.desiredSessionId = currentSessionIdFromStatus(payload);
    this.activeSessionId = payload.active_session_id || null;
    this.renderPageStatus(payload);
    if (!this.trackChangeInFlight) {
      this.applyTrackSelections(payload);
    }
    this.renderTimeline();

    if (Array.isArray(payload.errors) && payload.errors.length > 0) {
      this.setMessage(payload.errors[0].message, "error");
    } else if (Array.isArray(payload.warnings) && payload.warnings.length > 0) {
      this.setMessage(payload.warnings[0].message, "warning");
    } else if (!this.desiredSessionId) {
      this.setMessage("Waiting for a playback session.", "info");
    } else if (payload.pending_session_id) {
      this.setMessage("Buffering the latest session.", "info");
      this.setRuntimeState("buffering");
    } else {
      this.setMessage("Playback session ready.", "info");
    }
  };

  PlayerController.prototype.renderPageStatus = function(payload) {
    if (this.dom.statusState) {
      this.dom.statusState.textContent = payload.state;
      this.dom.statusState.className = "status-pill status-pill--" + payload.state;
    }
    if (this.dom.statusInfoHash) {
      this.dom.statusInfoHash.textContent = payload.info_hash || "Pending";
    }
    if (this.dom.statusDownloaded) {
      this.dom.statusDownloaded.textContent = String(payload.video_progress && payload.video_progress.bytes_downloaded || 0);
    }
    if (this.dom.statusTotal) {
      this.dom.statusTotal.textContent = String(payload.video_progress && payload.video_progress.bytes_total || 0);
    }
    if (this.dom.statusDuration) {
      this.dom.statusDuration.textContent = isFiniteNumber(payload.duration_seconds) ? payload.duration_seconds.toFixed(2) + "s" : "Unknown";
    }
    if (this.dom.statusSession) {
      this.dom.statusSession.textContent = payload.current_session_id || "None";
    }
  };

  PlayerController.prototype.applyTrackSelections = function(payload) {
    var playback = payload.playback || {};
    setSelectValue(this.dom.audioSelect, playback.selected_audio);
    setSelectValue(this.dom.subtitleSelect, playback.selected_subtitle);
  };

  // Reattaches an already-active playlist when the user reloads a media page.
  PlayerController.prototype.attachBootstrapPlaylist = function() {
    var payload = bootstrapPlaylistPayload(this.mediaStatus);
    if (!payload || !payload.session_id || !payload.playlist_url) {
      logDebug("no bootstrap playlist to attach", summarizeMediaStatus(this.mediaStatus));
      return;
    }
    logDebug("attaching bootstrap playlist", payload);
    this.currentPlaylistSessionId = payload.session_id;
    syncSubtitleTrack(this.dom.video, payload.subtitle_mode === "hls" ? null : payload.subtitle_url);
    this.attachPlaylist(payload.playlist_url, { subtitleMode: payload.subtitle_mode });
  };

  PlayerController.prototype.startPlayback = function() {
    var self = this;
    var selectedFile = this.mediaStatus.selected_file_index;
    if (selectedFile === null || selectedFile === undefined) {
      logError("playback start blocked: no selected video file", summarizeMediaStatus(this.mediaStatus));
      this.setMessage("Select a video file before starting playback.", "error");
      return;
    }

    this.setRuntimeState("starting");
    logDebug("starting playback", {
      media_id: this.mediaId,
      selected_file_index: selectedFile,
      selected_audio: selectValue(this.dom.audioSelect),
      selected_subtitle: selectValue(this.dom.subtitleSelect)
    });
    postJson("/media/" + this.mediaId + "/play", {
      file_index: selectedFile,
      start_time_seconds: 0,
      selected_audio: selectValue(this.dom.audioSelect),
      selected_subtitle: selectValue(this.dom.subtitleSelect)
    }).then(function(session) {
      logDebug("playback session requested", session);
      self.desiredSessionId = session.session_id;
      self.setMessage("Starting playback session.", "info");
      self.pollPlayback();
    }).catch(function(error) {
      logError("playback start failed", summarizeError(error));
      self.setRuntimeState("error");
      self.setMessage(error.message, "error");
    });
  };

  PlayerController.prototype.stopPlayback = function() {
    var self = this;
    var sessionId = stopTargetSessionId(this.currentPlaylistSessionId, this.activeSessionId, this.desiredSessionId);
    if (!sessionId) {
      logDebug("stop ignored: no active session", {
        current_playlist_session_id: this.currentPlaylistSessionId,
        active_session_id: this.activeSessionId,
        desired_session_id: this.desiredSessionId
      });
      this.setMessage("No active session to stop.", "info");
      return;
    }

    this.setRuntimeState("stopping");
    logDebug("stopping playback", { session_id: sessionId });
    postJson("/sessions/" + sessionId + "/stop", {}).then(function() {
      logDebug("stop request accepted", { session_id: sessionId });
      self.setMessage("Stopping playback session.", "info");
      self.pollMedia();
    }).catch(function(error) {
      logError("stop request failed", {
        session_id: sessionId,
        error: summarizeError(error)
      });
      self.setRuntimeState("error");
      self.setMessage(error.message, "error");
    });
  };

  PlayerController.prototype.scheduleSeek = function(targetSeconds) {
    var self = this;
    if (!isFiniteNumber(this.mediaStatus.duration_seconds)) {
      logDebug("seek ignored: duration unknown", summarizeMediaStatus(this.mediaStatus));
      this.setMessage("Seek is disabled until duration is known.", "info");
      return;
    }

    if (this.seekTimer) {
      globalObject.clearTimeout(this.seekTimer);
    }
    this.setRuntimeState("seeking");
    this.seekTimer = globalObject.setTimeout(function() {
      self.seekTimer = null;
      self.performSeek(targetSeconds);
    }, 160);
  };

  // Seeks on the global media timeline by asking the transcoder for a replacement session.
  // The old playlist can keep playing until the replacement is published as active.
  PlayerController.prototype.performSeek = function(targetSeconds) {
    var self = this;
    var clamped = clampTargetSeconds(targetSeconds, this.mediaStatus.duration_seconds);
    this.trackChangeInFlight = true;
    logDebug("seeking playback", {
      requested_seconds: targetSeconds,
      clamped_seconds: clamped,
      selected_audio: selectValue(this.dom.audioSelect),
      selected_subtitle: selectValue(this.dom.subtitleSelect)
    });
    postJson("/media/" + this.mediaId + "/seek", {
      target_seconds: clamped,
      selected_audio: selectValue(this.dom.audioSelect),
      selected_subtitle: selectValue(this.dom.subtitleSelect)
    }).then(function(session) {
      logDebug("seek session requested", session);
      self.desiredSessionId = session.session_id;
      self.setMessage("Seeking to " + formatClock(clamped) + ".", "info");
      self.pollPlayback();
    }).catch(function(error) {
      logError("seek failed", summarizeError(error));
      self.setRuntimeState("error");
      self.setMessage(error.message, "error");
    }).finally(function() {
      self.trackChangeInFlight = false;
    });
  };

  PlayerController.prototype.changeTrackSelection = function() {
    var sessionId = this.currentPlaylistSessionId || this.activeSessionId || this.desiredSessionId;
    if (!sessionId) {
      logDebug("track selection ignored: no session");
      return;
    }
    logDebug("track selection changed", {
      session_id: sessionId,
      selected_audio: selectValue(this.dom.audioSelect),
      selected_subtitle: selectValue(this.dom.subtitleSelect),
      current_global_time: this.currentGlobalTime()
    });
    this.performSeek(this.currentGlobalTime());
  };

  PlayerController.prototype.pollMedia = function() {
    var self = this;
    getJson("/media/" + this.mediaId + "/status.json").then(function(payload) {
      self.renderFromMediaStatus(payload);
    }).catch(function(error) {
      logError("media status poll failed", summarizeError(error));
      self.setMessage(error.message, "error");
    }).finally(function() {
      globalObject.setTimeout(function() {
        self.pollMedia();
      }, 1500);
    });
  };

  // Polls the desired session until it becomes playable. Each poll checks the
  // session id again because rapid seeks can leave older requests in flight.
  PlayerController.prototype.pollPlayback = function() {
    var self = this;
    var sessionId = this.desiredSessionId;
    if (!sessionId) {
      return;
    }

    getJson("/sessions/" + sessionId + "/status.json").then(function(payload) {
      // A previous poll can resolve after a newer seek has changed the desired session.
      if (!shouldApplySessionStatus(self.desiredSessionId, payload)) {
        logDebug("ignoring obsolete session status", {
          expected_session_id: self.desiredSessionId,
          payload: summarizePlaybackStatus(payload)
        });
        return;
      }
      var playbackSummary = summarizePlaybackStatus(payload);
      var playbackSignature = debugSignature(playbackSummary);
      if (playbackSignature !== self.lastPlaybackDebugSignature) {
        logDebug("session status changed", playbackSummary);
        self.lastPlaybackDebugSignature = playbackSignature;
        if (payload.error) {
          logError("session status reports error", playbackSummary);
        }
      }
      self.setRuntimeState(payload.state);
      if (payload.state === "hls_ready" || payload.state === "playing") {
        self.loadActivePlaylist(payload.session_id);
      }
    }).catch(function(error) {
      logError("session status poll failed", {
        session_id: sessionId,
        error: summarizeError(error)
      });
      self.pollMedia();
    }).finally(function() {
      globalObject.setTimeout(function() {
        if (self.desiredSessionId === sessionId && self.runtimeState !== "stopped") {
          self.pollPlayback();
        }
      }, 1000);
    });
  };

  // Loads the server-approved active playlist, not just the session that reported ready.
  // This extra hop lets the server hide pending sessions until their playlists and segments are safe to attach.
  PlayerController.prototype.loadActivePlaylist = function(expectedSessionId) {
    var self = this;
    logDebug("loading active playlist", { expected_session_id: expectedSessionId });
    getJson("/media/" + this.mediaId + "/active-playlist.json").then(function(payload) {
      // During rapid seeks, active-playlist can briefly describe the old active session.
      if (!shouldLoadPlaylist(expectedSessionId, payload)) {
        logDebug("ignoring active playlist payload", {
          expected_session_id: expectedSessionId,
          payload: payload
        });
        return;
      }
      if (self.currentPlaylistSessionId === payload.session_id && self.dom.video.src) {
        logDebug("active playlist already attached", {
          session_id: payload.session_id,
          video: summarizeVideo(self.dom.video)
        });
        return;
      }
      logDebug("active playlist accepted", payload);
      self.currentPlaylistSessionId = payload.session_id;
      self.mediaStatus.playback = {
        active_session_id: payload.session_id,
        session_start_time_seconds: payload.session_start_time_seconds || 0,
        playlist_url: payload.playlist_url,
        subtitle_url: payload.subtitle_url,
        subtitle_mode: payload.subtitle_mode || "none"
      };
      syncSubtitleTrack(self.dom.video, payload.subtitle_mode === "hls" ? null : payload.subtitle_url);
      self.attachPlaylist(payload.playlist_url, { subtitleMode: payload.subtitle_mode || "none" });
      self.renderTimeline();
      self.setRuntimeState("playing");
      self.setMessage("Playback ready.", "info");
    }).catch(function(error) {
      logError("active playlist load failed", summarizeError(error));
      self.setRuntimeState("error");
      self.setMessage(error.message, "error");
    });
  };

  // Attaches the HLS playlist through native playback where possible and hls.js otherwise.
  // Subtitle handling differs between sidecar tracks and HLS subtitle renditions, so the caller passes the mode from the server payload.
  PlayerController.prototype.attachPlaylist = function(playlistUrl, options) {
    var video = this.dom.video;
    var subtitleMode = options && options.subtitleMode || "none";
    if (!playlistUrl) {
      logError("attach playlist called without playlist URL");
      return;
    }

    var support = hlsSupportSummary(video);
    logDebug("attach playlist", {
      playlist_url: playlistUrl,
      subtitle_mode: subtitleMode,
      support: support,
      video: summarizeVideo(video)
    });
    if (this.hls) {
      logDebug("destroying previous hls.js instance");
      this.hls.destroy();
      this.hls = null;
    }

    if (support.nativeHls) {
      logDebug("using native HLS", {
        playlist_url: playlistUrl,
        native_can_play_type: support.nativeCanPlayType
      });
      this.playlistAttached = true;
      setVideoControlsEnabled(video, true);
      video.src = playlistUrl;
      video.load();
      requestVideoPlay(video, { mode: "native-hls", playlist_url: playlistUrl });
      return;
    }

    if (globalObject.Hls && support.hlsJsSupported) {
      var self = this;
      var events = globalObject.Hls.Events || {};
      logDebug("using hls.js", {
        playlist_url: playlistUrl,
        hls_version: globalObject.Hls.version || null
      });
      this.playlistAttached = true;
      setVideoControlsEnabled(video, true);
      this.hls = new globalObject.Hls();
      if (events.MEDIA_ATTACHED) {
        this.hls.on(events.MEDIA_ATTACHED, function(_event, data) {
          logDebug("hls.js media attached", {
            payload: data || null,
            video: summarizeVideo(video)
          });
        });
      }
      if (events.MANIFEST_LOADING) {
        this.hls.on(events.MANIFEST_LOADING, function(_event, data) {
          logDebug("hls.js manifest loading", data || null);
        });
      }
      if (events.MANIFEST_LOADED) {
        this.hls.on(events.MANIFEST_LOADED, function(_event, data) {
          logDebug("hls.js manifest loaded", data || null);
        });
      }
      if (events.MANIFEST_PARSED) {
        this.hls.on(events.MANIFEST_PARSED, function(_event, data) {
          logDebug("hls.js manifest parsed", data || null);
          if (subtitleMode === "hls") {
            activateFirstHlsSubtitle(self.hls);
          }
        });
      }
      if (events.SUBTITLE_TRACKS_UPDATED) {
        this.hls.on(events.SUBTITLE_TRACKS_UPDATED, function(_event, data) {
          logDebug("hls.js subtitle tracks updated", data || null);
          if (subtitleMode === "hls") {
            activateFirstHlsSubtitle(self.hls);
          }
        });
      }
      if (events.LEVEL_LOADED) {
        this.hls.on(events.LEVEL_LOADED, function(_event, data) {
          logDebug("hls.js level loaded", data || null);
        });
      }
      if (events.ERROR) {
        this.hls.on(events.ERROR, function(_event, data) {
          logError("hls.js error", {
            payload: data || null,
            video: summarizeVideo(video)
          });
          if (data && data.fatal) {
            self.setRuntimeState("error");
            self.setMessage("Playback failed while loading HLS.", "error");
          }
        });
      }
      this.hls.loadSource(playlistUrl);
      this.hls.attachMedia(video);
      requestVideoPlay(video, { mode: "hls.js", playlist_url: playlistUrl });
      return;
    }

    logError("unsupported HLS playback", {
      playlist_url: playlistUrl,
      support: support,
      video: summarizeVideo(video)
    });
    this.setRuntimeState("unsupported");
    this.setMessage("This browser needs native HLS or a local hls.js bundle.", "error");
  };

  function initFromDom() {
    var root = document.querySelector("[data-player-root]");
    var bootstrapNode = document.getElementById("media-bootstrap");
    if (!root || !bootstrapNode) {
      return null;
    }
    var bootstrap = JSON.parse(bootstrapNode.textContent);
    var controller = new PlayerController(root, bootstrap);
    controller.init();
    return controller;
  }

  var exportsObject = {
    PlayerController: PlayerController,
    bootstrapPlaylistPayload: bootstrapPlaylistPayload,
    activateFirstHlsSubtitle: activateFirstHlsSubtitle,
    clampTargetSeconds: clampTargetSeconds,
    currentSessionIdFromStatus: currentSessionIdFromStatus,
    deriveTimelineState: deriveTimelineState,
    formatClock: formatClock,
    initFromDom: initFromDom,
    hlsSupportSummary: hlsSupportSummary,
    mediaStructureSignature: mediaStructureSignature,
    shouldApplySessionStatus: shouldApplySessionStatus,
    shouldLoadPlaylist: shouldLoadPlaylist,
    shouldRefreshMediaPage: shouldRefreshMediaPage,
    stopTargetSessionId: stopTargetSessionId,
    syncSubtitleTrack: syncSubtitleTrack
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = exportsObject;
  } else {
    globalObject.TorrentPlayerUI = exportsObject;
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", initFromDom);
    } else {
      initFromDom();
    }
  }
})(typeof window !== "undefined" ? window : globalThis);
