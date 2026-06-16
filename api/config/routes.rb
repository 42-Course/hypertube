Rails.application.routes.draw do
  devise_for :users,
             controllers: { omniauth_callbacks: "users/omniauth_callbacks" }
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"

  use_doorkeeper

  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"

  namespace :api do
    namespace :v1 do
      # Email/username + password login. Mints a first-party access token
      # without requiring OAuth client credentials (POST create / DELETE destroy).
      resource :session, only: %i[create destroy], controller: "sessions"

      # Forgot-password flow (request reset email + set new password via token).
      resource :password, only: %i[create update], controller: "passwords"

      resources :users, only: %i[index show update create]

      resources :movies, only: %i[index show] do
        # Discovery against the external sources (TMDb + Prowlarr); /movies
        # itself only browses films already saved in our DB.
        get :search, on: :collection

        # Subject: comments are reachable via /movies/:id/comments (list + create).
        resources :comments, only: %i[index create]
      end

      # Subject: "POST /comments OR POST /movies/:movie_id/comments"
      resources :comments, only: %i[index show create update destroy]
    end
  end
end
