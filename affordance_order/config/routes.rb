Rails.application.routes.draw do
  namespace :api do
    post "clients/register", to: "clients#create"
    get "clients/me", to: "clients#me"

    post "providers/register", to: "providers#create"
    get "providers/me", to: "providers#me"

    resources :cards, only: [:index, :create, :destroy] do
      patch :default, on: :member, action: :set_default
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
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
