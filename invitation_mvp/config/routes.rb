Rails.application.routes.draw do
  namespace :api do
    post "clients/register", to: "clients#create"
    get "clients/me", to: "clients#me"

    post "providers/register", to: "providers#create"
    get "providers/me", to: "providers#me"

    resources :cards, only: [:index, :create, :destroy] do
      patch :default, on: :member, action: :set_default
    end

    resources :requests, only: [:index, :show, :create] do
      member do
        patch :accept
        patch :decline
      end
    end
  end

  namespace :admin do
    get "/", to: "dashboard#index"
    get "dashboard", to: "dashboard#index"
    resources :requests, only: [:index, :show]
    resources :clients, only: [:index, :show]
    resources :providers, only: [:index, :show]
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
