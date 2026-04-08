module Admin
  class AnnouncementsController < BaseController
    def index
      scope = Announcement.includes(:client)
      scope = scope.by_state(params[:state])
      scope = scope.where(client_id: params[:client_id]) if params[:client_id].present?
      scope = scope.order(created_at: :desc)
      @announcements = paginate(scope)
      @total_count = scope.count
    end

    def show
      @announcement = Announcement.includes(:client, requests: :provider).find(params[:id])
    end
  end
end
