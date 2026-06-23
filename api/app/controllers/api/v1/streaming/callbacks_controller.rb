module Api
  module V1
    module Streaming
      # Receives machine-to-machine callbacks from the torrent streaming service.
      # Authenticated not by a user's Doorkeeper token but by a service-scope
      # stream token signed with the shared STREAM_TICKET_SECRET (the same
      # contract StreamTicket mints/verifies), so no user context is required.
      class CallbacksController < ApplicationController
        skip_before_action :doorkeeper_authorize!
        before_action :authenticate_service!

        # POST /api/v1/streaming/callbacks/download_complete
        #
        # The streaming service calls this once a media has fully downloaded (and
        # its VOD is ready). We persist file_path so the API knows a downloaded
        # copy exists (and the catalog can show it / prefer VOD playback).
        def download_complete
          movie = find_movie
          return render json: { error: "movie_not_found" }, status: :not_found unless movie

          media_id  = params[:media_id].presence
          # Prefer the concrete VOD path; fall back to an identifier so the row is
          # still flagged downloaded when a path is not supplied yet.
          file_path = params[:file_path].presence || media_id || params[:info_hash].presence

          updates = { file_path: file_path }
          updates[:media_id] = media_id if media_id && movie.media_id.blank?
          duration_seconds = params[:duration_seconds].to_i
          if duration_seconds.positive? && movie.duration.blank?
            updates[:duration] = (duration_seconds / 60.0).round
          end
          movie.update!(updates)

          render json: { status: "ok", movie_id: movie.id }
        end

        private

        def authenticate_service!
          claims = StreamTicket.verify(bearer_token)
          unless claims["scope"] == StreamTicket::SERVICE_SCOPE
            raise StreamTicket::Error, "service scope required"
          end
        rescue StreamTicket::Error => e
          render json: { error: "unauthorized", message: e.message }, status: :unauthorized
        end

        def bearer_token
          header = request.headers["Authorization"].to_s
          header.start_with?("Bearer ") ? header.split(" ", 2).last : header
        end

        # Resolve the movie from the media id (captured at ticket time) first,
        # falling back to the torrent info hash matched against magnet_hash.
        def find_movie
          media_id  = params[:media_id].presence
          info_hash = params[:info_hash].to_s.downcase.presence

          movie = Movie.find_by(media_id: media_id) if media_id
          movie ||= Movie.where("LOWER(magnet_hash) = ?", info_hash).first if info_hash
          movie
        end
      end
    end
  end
end
