Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"

  use_doorkeeper

  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"

  # namespace :api do
  #   namespace :v1 do
  #     resources :users, only: %i[index show update]

  #     resources :movies, only: %i[index show] do
  #       resources :comments, only: %i[create]
  #     end

  #     resources :comments, only: %i[index show update destroy]
  #   end
  # end
end
