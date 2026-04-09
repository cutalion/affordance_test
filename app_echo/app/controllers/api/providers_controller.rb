module Api
  class ProvidersController < BaseController
    skip_before_action :authenticate!, only: [:create]

    def create
      provider = Provider.new(provider_params)
      if provider.save
        render json: provider_json(provider), status: :created
      else
        render_unprocessable(provider.errors.full_messages)
      end
    end

    def me
      provider = current_provider!
      return if performed?
      render json: provider_json(provider)
    end

    private

    def provider_params
      params.permit(:email, :name, :phone, :specialization)
    end

    def provider_json(provider)
      {
        id: provider.id,
        email: provider.email,
        name: provider.name,
        phone: provider.phone,
        specialization: provider.specialization,
        rating: provider.rating,
        api_token: provider.api_token
      }
    end
  end
end
