Rails.application.routes.draw do
  devise_for :users,
             controllers: { omniauth_callbacks: "users/omniauth_callbacks" }

  get "up" => "rails/health#show", as: :rails_health_check

  use_doorkeeper

  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"

  namespace :api do
    namespace :v1 do
      resource :session, only: %i[create destroy], controller: "sessions"

      resource :password, only: %i[create update], controller: "passwords"

      get "me", to: "users#me"

      resources :users, only: %i[index show update create] do
        # A user's watched movies (paginated).
        get :movies, on: :member
      end

      resources :movies, only: %i[index show] do
        # Discovery against the external sources (TMDb + Prowlarr); /movies
        # itself only browses films already saved in our DB.
        get :search, on: :collection

        # Mint a short-lived signed ticket so the browser can stream this movie
        # directly from the (separate) streaming service. See StreamTicket.
        post :stream_ticket, on: :member

        # Per-user watched flag: POST to mark watched, DELETE to clear it.
        member do
          post   "watched", action: :mark_watched
          delete "watched", action: :mark_unwatched, as: nil
        end

        # Subject: comments are reachable via /movies/:id/comments (list + create).
        resources :comments, only: %i[index create]
      end

      # Subject: "POST /comments OR POST /movies/:movie_id/comments"
      resources :comments, only: %i[index show create update destroy]
    end
  end
end
