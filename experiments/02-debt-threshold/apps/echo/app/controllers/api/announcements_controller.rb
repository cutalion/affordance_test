module Api
  class AnnouncementsController < BaseController
    before_action :set_announcement, only: [:show, :publish, :close, :respond]

    def index
      announcements = Announcement.published.sorted.page(params[:page])
      render json: announcements.map { |a| announcement_json(a) }
    end

    def show
      render json: announcement_detail_json(@announcement)
    end

    def create
      client = current_client!
      return if performed?

      result = Announcements::CreateService.new(client: client, params: announcement_params).call

      if result[:success]
        render json: announcement_detail_json(result[:announcement]), status: :created
      else
        render_unprocessable(result[:errors].full_messages)
      end
    end

    def publish
      client = current_client!
      return if performed?

      result = Announcements::PublishService.new(announcement: @announcement, client: client).call
      handle_result(result, :announcement)
    end

    def close
      client = current_client!
      return if performed?

      result = Announcements::CloseService.new(announcement: @announcement, client: client).call
      handle_result(result, :announcement)
    end

    def respond
      provider = current_provider!
      return if performed?

      # In the debt app, responding to an announcement creates a Request
      request = Request.new(
        client: @announcement.client,
        provider: provider,
        announcement: @announcement,
        scheduled_at: @announcement.scheduled_at || 3.days.from_now,
        duration_minutes: @announcement.duration_minutes || 120,
        location: @announcement.location,
        notes: "Response to announcement: #{@announcement.title}",
        amount_cents: params[:proposed_amount_cents] || @announcement.budget_cents || 0,
        currency: @announcement.currency,
        response_message: params[:message],
        proposed_amount_cents: params[:proposed_amount_cents]
      )

      if request.save
        NotificationService.notify(@announcement.client, :announcement_response, announcement_id: @announcement.id)
        render json: request_json(request), status: :created
      else
        render_unprocessable(request.errors.full_messages)
      end
    end

    private

    def set_announcement
      @announcement = Announcement.find_by(id: params[:id])
      render_not_found unless @announcement
    end

    def announcement_params
      params.permit(:title, :description, :location, :scheduled_at, :duration_minutes, :budget_cents, :currency)
    end

    def handle_result(result, key)
      if result[:success]
        render json: announcement_detail_json(result[key])
      else
        render json: { error: result[:error] }, status: :unprocessable_entity
      end
    end

    def announcement_json(a)
      { id: a.id, title: a.title, state: a.state, client_id: a.client_id, created_at: a.created_at }
    end

    def announcement_detail_json(a)
      {
        id: a.id, title: a.title, description: a.description, location: a.location,
        scheduled_at: a.scheduled_at, duration_minutes: a.duration_minutes,
        budget_cents: a.budget_cents, currency: a.currency, state: a.state,
        client_id: a.client_id, published_at: a.published_at, closed_at: a.closed_at,
        responses: a.requests.map { |r| request_json(r) },
        created_at: a.created_at, updated_at: a.updated_at
      }
    end

    def request_json(r)
      { id: r.id, state: r.state, provider_id: r.provider_id, message: r.response_message, proposed_amount_cents: r.proposed_amount_cents }
    end
  end
end
