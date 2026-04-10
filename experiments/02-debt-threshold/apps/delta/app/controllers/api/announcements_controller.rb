module Api
  class AnnouncementsController < BaseController
    before_action :set_announcement, only: [:show, :publish, :close]

    def index
      announcements = Announcement.all
      announcements = announcements.by_state(params[:state]) if params[:state].present?
      announcements = announcements.sorted.page(params[:page])
      render json: announcements.map { |a| announcement_summary_json(a) }
    end

    def show
      render json: announcement_detail_json(@announcement)
    end

    def create
      client = current_client!
      return if performed?

      result = Announcements::CreateService.new(
        client: client,
        params: announcement_params
      ).call

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
      handle_service_result(result)
    end

    def close
      client = current_client!
      return if performed?

      result = Announcements::CloseService.new(announcement: @announcement, client: client).call
      handle_service_result(result)
    end

    private

    def set_announcement
      @announcement = Announcement.find_by(id: params[:id])
      render_not_found unless @announcement
    end

    def announcement_params
      params.permit(:title, :description, :location, :scheduled_at, :duration_minutes, :budget_cents, :currency)
    end

    def handle_service_result(result)
      if result[:success]
        render json: announcement_detail_json(result[:announcement])
      else
        render json: { error: result[:error] }, status: :unprocessable_entity
      end
    end

    def announcement_summary_json(announcement)
      {
        id: announcement.id,
        title: announcement.title,
        state: announcement.state,
        budget_cents: announcement.budget_cents,
        currency: announcement.currency,
        client_id: announcement.client_id,
        created_at: announcement.created_at
      }
    end

    def announcement_detail_json(announcement)
      {
        id: announcement.id,
        title: announcement.title,
        description: announcement.description,
        location: announcement.location,
        scheduled_at: announcement.scheduled_at,
        duration_minutes: announcement.duration_minutes,
        budget_cents: announcement.budget_cents,
        currency: announcement.currency,
        state: announcement.state,
        published_at: announcement.published_at,
        closed_at: announcement.closed_at,
        client_id: announcement.client_id,
        responses_count: announcement.responses.count,
        created_at: announcement.created_at,
        updated_at: announcement.updated_at
      }
    end
  end
end
