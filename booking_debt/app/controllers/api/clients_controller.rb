module Api
  class ClientsController < BaseController
    skip_before_action :authenticate!, only: [:create]

    def create
      client = Client.new(client_params)
      if client.save
        render json: client_json(client), status: :created
      else
        render_unprocessable(client.errors.full_messages)
      end
    end

    def me
      client = current_client!
      return if performed?
      render json: client_json(client)
    end

    private

    def client_params
      params.permit(:email, :name, :phone)
    end

    def client_json(client)
      {
        id: client.id,
        email: client.email,
        name: client.name,
        phone: client.phone,
        api_token: client.api_token
      }
    end
  end
end
