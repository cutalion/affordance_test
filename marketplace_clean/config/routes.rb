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

    resources :orders, only: [:index, :show, :create] do
      member do
        patch :confirm
        patch :start
        patch :complete
        patch :cancel
        patch :reject
      end
      resources :reviews, only: [:index, :create]
    end

    resources :payments, only: [:index, :show]

    resources :announcements, only: [:index, :show, :create] do
      member do
        patch :publish
        patch :close
      end
      resources :responses, only: [:index, :create]
    end

    resources :responses, only: [] do
      member do
        patch :select
        patch :reject
      end
    end
  end

  namespace :admin do
    get "/", to: "dashboard#index"
    get "dashboard", to: "dashboard#index"
    resources :requests, only: [:index, :show]
    resources :orders, only: [:index, :show]
    resources :clients, only: [:index, :show]
    resources :providers, only: [:index, :show]
    resources :payments, only: [:index, :show]
    resources :announcements, only: [:index, :show]
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
