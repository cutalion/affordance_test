# Technical Debt Threshold — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build 5 Rails apps simulating domain evolution (invitation MVP → booking clean/debt → marketplace clean/debt) plus experiment infrastructure to test at what level of tech debt AI agents start making poor design decisions.

**Architecture:** Each app is a standalone Rails 8.1 API+admin app following the exact patterns established in the existing affordance_order app (AASM state machines, service objects, API controllers with bearer auth, admin HTML section with basic auth). Apps build on each other: MVP is the base, booking apps fork from MVP, marketplace apps fork from booking apps.

**Tech Stack:** Ruby 3.3.5, Rails 8.1.3, SQLite, AASM, RSpec + FactoryBot + Shoulda-matchers + DatabaseCleaner

---

## File Structure

### Shared across all apps (identical to affordance_order)
- `Gemfile` — same dependencies
- `config/application.rb` — API mode + action_view for admin
- `config/initializers/admin_auth.rb` — basic auth config
- `app/models/application_record.rb`
- `app/models/concerns/paginatable.rb`
- `app/models/client.rb`, `app/models/provider.rb`, `app/models/card.rb`
- `app/controllers/application_controller.rb`
- `app/controllers/api/base_controller.rb` — bearer token auth
- `app/controllers/api/clients_controller.rb`, `api/providers_controller.rb`, `api/cards_controller.rb`
- `app/controllers/admin/base_controller.rb` — basic auth + pagination
- `app/controllers/admin/dashboard_controller.rb`
- `app/controllers/admin/clients_controller.rb`, `admin/providers_controller.rb`
- `app/views/admin/clients/`, `admin/providers/` — index + show views
- `app/services/notification_service.rb`
- `spec/rails_helper.rb`, `spec/spec_helper.rb`, `spec/support/notification_helpers.rb`
- `spec/factories/clients.rb`, `providers.rb`, `cards.rb`
- `db/migrate/` — clients, providers, cards migrations

### invitation_mvp (Stage 0)
- `app/models/request.rb` — states: pending, accepted, declined, expired
- `app/services/requests/create_service.rb`
- `app/services/requests/accept_service.rb`
- `app/services/requests/decline_service.rb`
- `app/controllers/api/requests_controller.rb`
- `app/controllers/admin/requests_controller.rb`
- `app/views/admin/requests/` — index + show
- `app/views/admin/dashboard/index.html.erb`
- `app/views/layouts/admin.html.erb`
- `db/migrate/xxx_create_requests.rb`
- `spec/models/request_spec.rb`
- `spec/services/requests/*_spec.rb`
- `spec/factories/requests.rb`
- `config/routes.rb`

### booking_clean (Stage 1 Clean) — MVP + Order
Additional files:
- `app/models/order.rb` — states: pending, confirmed, in_progress, completed, canceled, rejected
- `app/models/payment.rb`, `app/models/review.rb`
- `app/services/orders/` — create, confirm, start, complete, cancel, reject
- `app/services/payment_gateway.rb`
- `app/controllers/api/orders_controller.rb`, `api/reviews_controller.rb`, `api/payments_controller.rb`
- `app/controllers/admin/orders_controller.rb`, `admin/payments_controller.rb`
- `app/views/admin/orders/`, `admin/payments/`
- `db/migrate/xxx_create_orders.rb`, `xxx_create_payments.rb`, `xxx_create_reviews.rb`
- Modified: `app/services/requests/accept_service.rb` — now creates Order on accept
- Modified: `app/models/client.rb`, `provider.rb` — add `has_many :orders`
- Modified: `config/routes.rb` — add order/review/payment routes
- Modified: `app/views/layouts/admin.html.erb` — add Orders, Payments nav links
- Modified: `app/controllers/admin/dashboard_controller.rb` — add order stats

### booking_debt (Stage 1 Debt) — MVP with extended Request
Modified files:
- `app/models/request.rb` — states: pending, accepted, in_progress, completed, declined, expired, canceled, rejected
- `app/models/payment.rb`, `app/models/review.rb` — belong_to :request
- `app/services/requests/` — add start, complete, cancel, reject services; modify accept to capture payment
- `app/services/payment_gateway.rb`
- `app/controllers/api/requests_controller.rb` — add lifecycle actions
- `app/controllers/api/reviews_controller.rb`, `api/payments_controller.rb`
- `app/controllers/admin/payments_controller.rb`
- `db/migrate/xxx_create_requests.rb` — extended columns
- `db/migrate/xxx_create_payments.rb`, `xxx_create_reviews.rb` — reference :request

### marketplace_clean (Stage 2 Clean) — booking_clean + Announcement + Response
Additional files:
- `app/models/announcement.rb` — states: draft, published, closed
- `app/models/response.rb` — states: pending, selected, rejected
- `app/services/announcements/` — create, publish, close
- `app/services/responses/` — create, select, reject
- `app/controllers/api/announcements_controller.rb`, `api/responses_controller.rb`
- `app/controllers/admin/announcements_controller.rb`
- `app/views/admin/announcements/` — index + show
- `db/migrate/xxx_create_announcements.rb`, `xxx_create_responses.rb`
- Modified: `config/routes.rb`, admin layout, dashboard

### marketplace_debt (Stage 2 Debt) — booking_debt + Announcement + Request-as-response
Additional files:
- `app/models/announcement.rb` — states: draft, published, closed
- `app/services/announcements/` — create, publish, close
- `app/controllers/api/announcements_controller.rb`
- `app/controllers/admin/announcements_controller.rb`
- `app/views/admin/announcements/` — index + show
- `db/migrate/xxx_create_announcements.rb`
- Modified: `app/models/request.rb` — add `belongs_to :announcement, optional: true`
- Modified: `db/migrate/xxx_create_requests.rb` — add announcement_id
- Modified: `app/services/requests/accept_service.rb` — handles all three flows
- Modified: `config/routes.rb`, admin layout, dashboard

---

### Task 1: Create invitation_mvp Rails app

**Files:**
- Create: `invitation_mvp/` (entire Rails app)

- [ ] **Step 1: Generate Rails app**

```bash
cd /home/cutalion/code/affordance_test
rails new invitation_mvp --api --database=sqlite3 --skip-test --skip-action-mailbox --skip-action-text --skip-active-storage --skip-action-cable --skip-hotwire --skip-jbuilder --skip-docker --skip-kamal --skip-thruster --skip-ci --skip-brakeman --skip-rubocop
```

- [ ] **Step 2: Set up Gemfile**

Replace `invitation_mvp/Gemfile` with:

```ruby
source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "sqlite3", ">= 2.1"
gem "puma", ">= 5.0"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "solid_cache"
gem "solid_queue"
gem "bootsnap", require: false
gem "aasm"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "shoulda-matchers"
  gem "database_cleaner-active_record"
end
```

Run:
```bash
cd invitation_mvp && bundle install
```

- [ ] **Step 3: Configure application for API + admin views**

Replace `invitation_mvp/config/application.rb`:

```ruby
require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module InvitationMvp
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])
    config.api_only = true
  end
end
```

Create `invitation_mvp/config/initializers/admin_auth.rb`:

```ruby
Rails.application.config.admin_username = ENV.fetch("ADMIN_USERNAME", "admin")
Rails.application.config.admin_password = ENV.fetch("ADMIN_PASSWORD", "admin_password")
```

- [ ] **Step 4: Set up RSpec**

```bash
cd invitation_mvp && rails generate rspec:install
```

Replace `invitation_mvp/spec/rails_helper.rb`:

```ruby
require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods

  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
```

Create `invitation_mvp/spec/support/notification_helpers.rb`:

```ruby
module NotificationHelpers
  def notification_log_path
    Rails.root.join("log/notifications.log")
  end

  def payment_log_path
    Rails.root.join("log/payments.log")
  end

  def read_notification_log
    File.exist?(notification_log_path) ? File.read(notification_log_path) : ""
  end

  def read_payment_log
    File.exist?(payment_log_path) ? File.read(payment_log_path) : ""
  end

  def clear_notification_log
    File.write(notification_log_path, "") if File.exist?(notification_log_path)
  end

  def clear_payment_log
    File.write(payment_log_path, "") if File.exist?(payment_log_path)
  end
end

RSpec.configure do |config|
  config.include NotificationHelpers

  config.before(:each) do
    clear_notification_log
    clear_payment_log
  end
end
```

- [ ] **Step 5: Create migrations**

```bash
cd invitation_mvp
bin/rails generate migration CreateClients email:string name:string phone:string api_token:string notification_preferences:text
bin/rails generate migration CreateProviders email:string name:string phone:string api_token:string rating:decimal specialization:string active:boolean notification_preferences:text
bin/rails generate migration CreateCards client:references token:string last_four:string brand:string exp_month:integer exp_year:integer default:boolean
bin/rails generate migration CreateRequests client:references provider:references scheduled_at:datetime duration_minutes:integer location:string notes:text state:string
```

Then edit each migration to match exact patterns:

`db/migrate/xxx_create_clients.rb`:
```ruby
class CreateClients < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :phone
      t.string :api_token, null: false
      t.text :notification_preferences, null: false, default: '{"push":true,"sms":true,"email":true}'

      t.timestamps
    end

    add_index :clients, :email, unique: true
    add_index :clients, :api_token, unique: true
  end
end
```

`db/migrate/xxx_create_providers.rb`:
```ruby
class CreateProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :providers do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :phone
      t.string :api_token, null: false
      t.decimal :rating, precision: 3, scale: 2, default: 0.0
      t.string :specialization
      t.boolean :active, null: false, default: true
      t.text :notification_preferences, null: false, default: '{"push":true,"sms":true,"email":true}'

      t.timestamps
    end

    add_index :providers, :email, unique: true
    add_index :providers, :api_token, unique: true
  end
end
```

`db/migrate/xxx_create_cards.rb`:
```ruby
class CreateCards < ActiveRecord::Migration[8.1]
  def change
    create_table :cards do |t|
      t.references :client, null: false, foreign_key: true
      t.string :token, null: false
      t.string :last_four, null: false
      t.string :brand, null: false
      t.integer :exp_month, null: false
      t.integer :exp_year, null: false
      t.boolean :default, null: false, default: false

      t.timestamps
    end
  end
end
```

`db/migrate/xxx_create_requests.rb`:
```ruby
class CreateRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :requests do |t|
      t.references :client, null: false, foreign_key: true
      t.references :provider, null: false, foreign_key: true
      t.datetime :scheduled_at, null: false
      t.integer :duration_minutes, null: false
      t.string :location
      t.text :notes
      t.string :state, null: false, default: "pending"
      t.text :decline_reason
      t.datetime :accepted_at
      t.datetime :expired_at

      t.timestamps
    end

    add_index :requests, :state
    add_index :requests, :scheduled_at
  end
end
```

Run:
```bash
cd invitation_mvp && bin/rails db:create db:migrate
```

- [ ] **Step 6: Create models**

`invitation_mvp/app/models/concerns/paginatable.rb`:
```ruby
module Paginatable
  extend ActiveSupport::Concern

  included do
    scope :page, ->(page, per: 20) {
      page = [page.to_i, 1].max
      offset((page - 1) * per).limit(per)
    }
  end
end
```

`invitation_mvp/app/models/client.rb`:
```ruby
class Client < ApplicationRecord
  serialize :notification_preferences, coder: JSON

  has_many :requests, dependent: :destroy
  has_many :cards, dependent: :destroy

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :api_token, presence: true, uniqueness: true

  before_validation :generate_api_token, on: :create

  def default_card
    cards.find_by(default: true)
  end

  private

  def generate_api_token
    self.api_token ||= SecureRandom.hex(32)
  end
end
```

`invitation_mvp/app/models/provider.rb`:
```ruby
class Provider < ApplicationRecord
  serialize :notification_preferences, coder: JSON

  has_many :requests, dependent: :destroy

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :api_token, presence: true, uniqueness: true
  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }

  before_validation :generate_api_token, on: :create

  scope :active, -> { where(active: true) }

  private

  def generate_api_token
    self.api_token ||= SecureRandom.hex(32)
  end
end
```

`invitation_mvp/app/models/card.rb`:
```ruby
class Card < ApplicationRecord
  belongs_to :client

  validates :token, presence: true
  validates :last_four, presence: true, length: { is: 4 }
  validates :brand, presence: true, inclusion: { in: %w[visa mastercard amex mir] }
  validates :exp_month, presence: true, numericality: { in: 1..12 }
  validates :exp_year, presence: true, numericality: { greater_than_or_equal_to: 2024 }

  after_save :ensure_single_default

  def make_default!
    transaction do
      client.cards.where.not(id: id).update_all(default: false)
      update!(default: true)
    end
  end

  private

  def ensure_single_default
    if default? && client.cards.where(default: true).where.not(id: id).exists?
      client.cards.where(default: true).where.not(id: id).update_all(default: false)
    end
  end
end
```

`invitation_mvp/app/models/request.rb`:
```ruby
class Request < ApplicationRecord
  include AASM
  include Paginatable

  belongs_to :client
  belongs_to :provider

  validates :scheduled_at, presence: true
  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
  validates :decline_reason, presence: true, if: -> { declined? }

  scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
  scope :past, -> { where("scheduled_at <= ?", Time.current) }
  scope :by_state, ->(state) { where(state: state) if state.present? }
  scope :by_client, ->(client_id) { where(client_id: client_id) if client_id.present? }
  scope :by_provider, ->(provider_id) { where(provider_id: provider_id) if provider_id.present? }
  scope :scheduled_between, ->(from, to) {
    scope = all
    scope = scope.where("scheduled_at >= ?", from) if from.present?
    scope = scope.where("scheduled_at <= ?", to) if to.present?
    scope
  }
  scope :sorted, -> { order(scheduled_at: :desc) }

  aasm column: :state do
    state :pending, initial: true
    state :accepted
    state :declined
    state :expired

    event :accept do
      transitions from: :pending, to: :accepted
      after do
        update!(accepted_at: Time.current)
      end
    end

    event :decline do
      transitions from: :pending, to: :declined
    end

    event :expire do
      transitions from: :pending, to: :expired
      after do
        update!(expired_at: Time.current)
      end
    end
  end
end
```

- [ ] **Step 7: Create services**

`invitation_mvp/app/services/notification_service.rb`:
```ruby
class NotificationService
  LOG_PATH = -> { Rails.root.join("log/notifications.log") }

  def self.notify(recipient, event, payload = {})
    new(recipient, event, payload).deliver
  end

  def initialize(recipient, event, payload)
    @recipient = recipient
    @event = event
    @payload = payload
    @preferences = recipient.notification_preferences
  end

  def deliver
    send_push if @preferences["push"]
    send_sms if @preferences["sms"]
    send_email if @preferences["email"]
  end

  private

  def send_push
    log_notification("PUSH", "to=#{recipient_identifier} event=#{@event} #{payload_string}")
  end

  def send_sms
    log_notification("SMS", "to=#{@recipient.phone} event=#{@event} #{payload_string}")
  end

  def send_email
    log_notification("EMAIL", "to=#{@recipient.email} event=#{@event} #{payload_string}")
  end

  def recipient_identifier
    "#{@recipient.class.name.downcase}_#{@recipient.id}"
  end

  def payload_string
    @payload.map { |k, v| "#{k}=#{v}" }.join(" ")
  end

  def log_notification(channel, message)
    File.open(self.class::LOG_PATH.call, "a") do |f|
      f.puts "[#{channel}] #{message} at=#{Time.current.iso8601}"
    end
  end
end
```

`invitation_mvp/app/services/requests/create_service.rb`:
```ruby
module Requests
  class CreateService
    def initialize(client:, provider:, params:)
      @client = client
      @provider = provider
      @params = params
    end

    def call
      request = Request.new(
        client: @client,
        provider: @provider,
        scheduled_at: @params[:scheduled_at],
        duration_minutes: @params[:duration_minutes],
        location: @params[:location],
        notes: @params[:notes]
      )

      request.save!

      NotificationService.notify(@provider, :request_created, request_id: request.id)
      { success: true, request: request }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, errors: e.record.errors }
    end
  end
end
```

`invitation_mvp/app/services/requests/accept_service.rb`:
```ruby
module Requests
  class AcceptService
    def initialize(request:, provider:)
      @request = request
      @provider = provider
    end

    def call
      return error("Not your request") unless @request.provider_id == @provider.id

      @request.accept!
      NotificationService.notify(@request.client, :request_accepted, request_id: @request.id)
      { success: true, request: @request }
    rescue AASM::InvalidTransition
      error("Cannot accept request in #{@request.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

`invitation_mvp/app/services/requests/decline_service.rb`:
```ruby
module Requests
  class DeclineService
    def initialize(request:, provider:, reason:)
      @request = request
      @provider = provider
      @reason = reason
    end

    def call
      return error("Not your request") unless @request.provider_id == @provider.id
      return error("Decline reason is required") if @reason.blank?

      @request.decline_reason = @reason
      @request.decline!

      NotificationService.notify(@request.client, :request_declined, request_id: @request.id)
      { success: true, request: @request }
    rescue AASM::InvalidTransition
      error("Cannot decline request in #{@request.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

- [ ] **Step 8: Create controllers**

`invitation_mvp/app/controllers/api/base_controller.rb`:
```ruby
module Api
  class BaseController < ApplicationController
    before_action :authenticate!

    private

    def authenticate!
      token = extract_bearer_token
      return render_unauthorized unless token

      @current_user = Client.find_by(api_token: token) || Provider.find_by(api_token: token)
      render_unauthorized unless @current_user
    end

    def extract_bearer_token
      header = request.headers["Authorization"]
      return nil unless header&.start_with?("Bearer ")
      header.sub("Bearer ", "").strip
    end

    def current_user
      @current_user
    end

    def current_client!
      return current_user if current_user.is_a?(Client)
      render_forbidden
    end

    def current_provider!
      return current_user if current_user.is_a?(Provider)
      render_forbidden
    end

    def render_unauthorized
      render json: { error: "Unauthorized" }, status: :unauthorized
    end

    def render_forbidden
      render json: { error: "Forbidden" }, status: :forbidden
    end

    def render_not_found
      render json: { error: "Not found" }, status: :not_found
    end

    def render_unprocessable(errors)
      render json: { errors: errors }, status: :unprocessable_entity
    end
  end
end
```

`invitation_mvp/app/controllers/api/clients_controller.rb`:
```ruby
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
```

`invitation_mvp/app/controllers/api/providers_controller.rb`:
```ruby
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
```

`invitation_mvp/app/controllers/api/cards_controller.rb`:
```ruby
module Api
  class CardsController < BaseController
    before_action :require_client!
    before_action :set_card, only: [:destroy, :set_default]

    def index
      render json: current_user.cards.map { |c| card_json(c) }
    end

    def create
      is_first = current_user.cards.empty?
      card = current_user.cards.new(card_params)
      card.default = is_first if is_first

      if card.save
        render json: card_json(card), status: :created
      else
        render_unprocessable(card.errors.full_messages)
      end
    end

    def destroy
      @card.destroy
      head :no_content
    end

    def set_default
      @card.make_default!
      render json: card_json(@card)
    end

    private

    def require_client!
      render_forbidden unless current_user.is_a?(Client)
    end

    def set_card
      @card = current_user.cards.find_by(id: params[:id])
      render_not_found unless @card
    end

    def card_params
      params.permit(:token, :last_four, :brand, :exp_month, :exp_year, :default)
    end

    def card_json(card)
      {
        id: card.id,
        brand: card.brand,
        last_four: card.last_four,
        exp_month: card.exp_month,
        exp_year: card.exp_year,
        default: card.default
      }
    end
  end
end
```

`invitation_mvp/app/controllers/api/requests_controller.rb`:
```ruby
module Api
  class RequestsController < BaseController
    before_action :set_request, only: [:show, :accept, :decline]

    def index
      requests = scoped_requests
      requests = requests.by_state(params[:state]) if params[:state].present?
      requests = requests.scheduled_between(params[:from], params[:to])
      requests = requests.sorted.page(params[:page])
      render json: requests.map { |r| request_summary_json(r) }
    end

    def show
      render json: request_detail_json(@request)
    end

    def create
      client = current_client!
      return if performed?

      provider = Provider.find_by(id: params[:provider_id])
      return render_not_found unless provider

      result = Requests::CreateService.new(
        client: client,
        provider: provider,
        params: request_params
      ).call

      if result[:success]
        render json: request_detail_json(result[:request]), status: :created
      else
        render_unprocessable(result[:errors].full_messages)
      end
    end

    def accept
      provider = current_provider!
      return if performed?

      result = Requests::AcceptService.new(request: @request, provider: provider).call
      handle_service_result(result)
    end

    def decline
      provider = current_provider!
      return if performed?

      if params[:reason].blank?
        return render_unprocessable(["Reason is required"])
      end

      result = Requests::DeclineService.new(
        request: @request,
        provider: provider,
        reason: params[:reason]
      ).call
      handle_service_result(result)
    end

    private

    def set_request
      @request = Request.find_by(id: params[:id])
      render_not_found unless @request
    end

    def scoped_requests
      if current_user.is_a?(Client)
        Request.where(client: current_user)
      else
        Request.where(provider: current_user)
      end
    end

    def request_params
      params.permit(:scheduled_at, :duration_minutes, :location, :notes)
    end

    def handle_service_result(result)
      if result[:success]
        render json: request_detail_json(result[:request])
      else
        render json: { error: result[:error] }, status: :unprocessable_entity
      end
    end

    def request_summary_json(request)
      {
        id: request.id,
        state: request.state,
        scheduled_at: request.scheduled_at,
        client_id: request.client_id,
        provider_id: request.provider_id
      }
    end

    def request_detail_json(request)
      {
        id: request.id,
        state: request.state,
        scheduled_at: request.scheduled_at,
        duration_minutes: request.duration_minutes,
        location: request.location,
        notes: request.notes,
        decline_reason: request.decline_reason,
        accepted_at: request.accepted_at,
        expired_at: request.expired_at,
        client_id: request.client_id,
        provider_id: request.provider_id,
        created_at: request.created_at,
        updated_at: request.updated_at
      }
    end
  end
end
```

- [ ] **Step 9: Create admin controllers and views**

`invitation_mvp/app/controllers/admin/base_controller.rb`:
```ruby
module Admin
  class BaseController < ActionController::Base
    http_basic_authenticate_with(
      name: Rails.application.config.admin_username,
      password: Rails.application.config.admin_password
    )
    layout "admin"

    private

    def page_param
      [params[:page].to_i, 1].max
    end

    def per_page
      25
    end

    def paginate(scope)
      scope.offset((page_param - 1) * per_page).limit(per_page)
    end
  end
end
```

`invitation_mvp/app/controllers/admin/dashboard_controller.rb`:
```ruby
module Admin
  class DashboardController < BaseController
    def index
      @clients_count = Client.count
      @providers_count = Provider.count

      @requests_by_state = Request.group(:state).count
      @recent_requests = Request.includes(:client, :provider).order(created_at: :desc).limit(10)
    end
  end
end
```

`invitation_mvp/app/controllers/admin/requests_controller.rb`:
```ruby
module Admin
  class RequestsController < BaseController
    def index
      scope = Request.includes(:client, :provider)
      scope = scope.by_state(params[:state])
      scope = scope.scheduled_between(params[:from], params[:to])
      scope = scope.by_client(params[:client_id]) if params[:client_id].present?
      scope = scope.by_provider(params[:provider_id]) if params[:provider_id].present?
      scope = scope.order(created_at: :desc)
      @requests = paginate(scope)
      @total_count = scope.count
    end

    def show
      @request = Request.includes(:client, :provider).find(params[:id])
    end
  end
end
```

`invitation_mvp/app/controllers/admin/clients_controller.rb`:
```ruby
module Admin
  class ClientsController < BaseController
    def index
      @clients = paginate(Client.order(created_at: :desc))
      @total_count = Client.count
    end

    def show
      @client = Client.find(params[:id])
    end
  end
end
```

`invitation_mvp/app/controllers/admin/providers_controller.rb`:
```ruby
module Admin
  class ProvidersController < BaseController
    def index
      @providers = paginate(Provider.order(created_at: :desc))
      @total_count = Provider.count
    end

    def show
      @provider = Provider.find(params[:id])
    end
  end
end
```

`invitation_mvp/app/views/layouts/admin.html.erb`:
```erb
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Admin Panel</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f6fa; color: #333; }
    nav { background: #2c3e50; color: #fff; padding: 0 24px; display: flex; align-items: center; height: 56px; }
    nav .brand { font-size: 18px; font-weight: 700; margin-right: 32px; text-decoration: none; color: #fff; }
    nav a { color: #bdc3c7; text-decoration: none; margin-right: 20px; font-size: 14px; padding: 4px 0; }
    nav a:hover, nav a.active { color: #fff; border-bottom: 2px solid #3498db; }
    .container { max-width: 1200px; margin: 32px auto; padding: 0 24px; }
    h1 { font-size: 24px; margin-bottom: 24px; color: #2c3e50; }
    h2 { font-size: 18px; margin: 24px 0 12px; color: #2c3e50; }
    .stat-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 16px; margin-bottom: 32px; }
    .stat-card { background: #fff; border-radius: 8px; padding: 20px; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
    .stat-card .label { font-size: 13px; color: #7f8c8d; margin-bottom: 8px; }
    .stat-card .value { font-size: 28px; font-weight: 700; color: #2c3e50; }
    table { width: 100%; border-collapse: collapse; background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
    th { background: #f0f2f5; text-align: left; padding: 12px 16px; font-size: 13px; color: #7f8c8d; text-transform: uppercase; letter-spacing: 0.5px; }
    td { padding: 12px 16px; border-top: 1px solid #f0f2f5; font-size: 14px; }
    tr:hover td { background: #fafbfc; }
    a { color: #3498db; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .detail-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; margin-bottom: 32px; }
    .detail-card { background: #fff; border-radius: 8px; padding: 24px; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
    .detail-row { display: flex; padding: 8px 0; border-bottom: 1px solid #f0f2f5; font-size: 14px; }
    .detail-row:last-child { border-bottom: none; }
    .detail-label { width: 160px; color: #7f8c8d; flex-shrink: 0; }
    .detail-value { color: #2c3e50; font-weight: 500; }
    .filter-form { background: #fff; border-radius: 8px; padding: 16px 20px; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-bottom: 20px; display: flex; gap: 12px; align-items: flex-end; flex-wrap: wrap; }
    .filter-form label { font-size: 13px; color: #7f8c8d; display: block; margin-bottom: 4px; }
    .filter-form select, .filter-form input[type=date], .filter-form input[type=text] { border: 1px solid #dde1e7; border-radius: 4px; padding: 6px 10px; font-size: 14px; color: #333; }
    .filter-form button { background: #3498db; color: #fff; border: none; border-radius: 4px; padding: 7px 16px; font-size: 14px; cursor: pointer; }
    .filter-form button:hover { background: #2980b9; }
    .badge { display: inline-block; padding: 3px 8px; border-radius: 12px; font-size: 12px; font-weight: 600; }
    .badge-pending { background: #fef9e7; color: #d68910; }
    .badge-accepted { background: #eaf4fb; color: #2980b9; }
    .badge-declined { background: #fdedec; color: #c0392b; }
    .badge-expired { background: #fdfefe; color: #717d7e; border: 1px solid #d0d3d4; }
    .back-link { display: inline-block; margin-bottom: 16px; font-size: 14px; }
    .pagination { margin-top: 16px; font-size: 14px; color: #7f8c8d; }
  </style>
</head>
<body>
  <nav>
    <a href="/admin" class="brand">Request Admin</a>
    <a href="/admin/dashboard">Dashboard</a>
    <a href="/admin/requests">Requests</a>
    <a href="/admin/clients">Clients</a>
    <a href="/admin/providers">Providers</a>
  </nav>
  <div class="container">
    <%= yield %>
  </div>
</body>
</html>
```

`invitation_mvp/app/views/admin/dashboard/index.html.erb`:
```erb
<h1>Dashboard</h1>

<div class="stat-grid">
  <div class="stat-card">
    <div class="label">Clients</div>
    <div class="value"><%= @clients_count %></div>
  </div>
  <div class="stat-card">
    <div class="label">Providers</div>
    <div class="value"><%= @providers_count %></div>
  </div>
  <% %w[pending accepted declined expired].each do |state| %>
    <div class="stat-card">
      <div class="label">Requests <span class="badge badge-<%= state %>"><%= state.humanize %></span></div>
      <div class="value"><%= @requests_by_state[state] || 0 %></div>
    </div>
  <% end %>
</div>

<h2>Recent Requests</h2>
<table>
  <thead>
    <tr>
      <th>ID</th>
      <th>Client</th>
      <th>Provider</th>
      <th>State</th>
      <th>Scheduled</th>
      <th>Created</th>
    </tr>
  </thead>
  <tbody>
    <% @recent_requests.each do |request| %>
      <tr>
        <td><%= link_to "##{request.id}", admin_request_path(request) %></td>
        <td><%= request.client.name %></td>
        <td><%= request.provider.name %></td>
        <td><span class="badge badge-<%= request.state %>"><%= request.state.humanize %></span></td>
        <td><%= request.scheduled_at&.strftime("%Y-%m-%d %H:%M") %></td>
        <td><%= request.created_at&.strftime("%Y-%m-%d") %></td>
      </tr>
    <% end %>
    <% if @recent_requests.empty? %>
      <tr><td colspan="6" style="text-align:center; color:#7f8c8d;">No requests yet</td></tr>
    <% end %>
  </tbody>
</table>
```

`invitation_mvp/app/views/admin/requests/index.html.erb`:
```erb
<h1>Requests (<%= @total_count %>)</h1>

<div class="filter-form">
  <%= form_tag(admin_requests_path, method: :get) do %>
    <div>
      <label>State</label>
      <%= select_tag :state, options_for_select([["All", ""], "pending", "accepted", "declined", "expired"], params[:state]) %>
    </div>
    <div>
      <label>From</label>
      <%= date_field_tag :from, params[:from] %>
    </div>
    <div>
      <label>To</label>
      <%= date_field_tag :to, params[:to] %>
    </div>
    <div>
      <button type="submit">Filter</button>
    </div>
  <% end %>
</div>

<table>
  <thead>
    <tr>
      <th>ID</th>
      <th>Client</th>
      <th>Provider</th>
      <th>State</th>
      <th>Scheduled</th>
      <th>Created</th>
    </tr>
  </thead>
  <tbody>
    <% @requests.each do |request| %>
      <tr>
        <td><%= link_to "##{request.id}", admin_request_path(request) %></td>
        <td><%= link_to request.client.name, admin_client_path(request.client) %></td>
        <td><%= link_to request.provider.name, admin_provider_path(request.provider) %></td>
        <td><span class="badge badge-<%= request.state %>"><%= request.state.humanize %></span></td>
        <td><%= request.scheduled_at&.strftime("%Y-%m-%d %H:%M") %></td>
        <td><%= request.created_at&.strftime("%Y-%m-%d") %></td>
      </tr>
    <% end %>
    <% if @requests.empty? %>
      <tr><td colspan="6" style="text-align:center; color:#7f8c8d;">No requests found</td></tr>
    <% end %>
  </tbody>
</table>

<div class="pagination">
  Showing <%= @requests.length %> of <%= @total_count %> requests
</div>
```

`invitation_mvp/app/views/admin/requests/show.html.erb`:
```erb
<%= link_to "&larr; Back to Requests".html_safe, admin_requests_path, class: "back-link" %>
<h1>Request #<%= @request.id %></h1>

<div class="detail-grid">
  <div class="detail-card">
    <h2>Request Details</h2>
    <div class="detail-row"><span class="detail-label">ID</span><span class="detail-value"><%= @request.id %></span></div>
    <div class="detail-row"><span class="detail-label">State</span><span class="detail-value"><span class="badge badge-<%= @request.state %>"><%= @request.state.humanize %></span></span></div>
    <div class="detail-row"><span class="detail-label">Client</span><span class="detail-value"><%= link_to @request.client.name, admin_client_path(@request.client) %></span></div>
    <div class="detail-row"><span class="detail-label">Provider</span><span class="detail-value"><%= link_to @request.provider.name, admin_provider_path(@request.provider) %></span></div>
    <div class="detail-row"><span class="detail-label">Scheduled At</span><span class="detail-value"><%= @request.scheduled_at&.strftime("%Y-%m-%d %H:%M") %></span></div>
    <div class="detail-row"><span class="detail-label">Duration</span><span class="detail-value"><%= @request.duration_minutes %> min</span></div>
    <div class="detail-row"><span class="detail-label">Location</span><span class="detail-value"><%= @request.location %></span></div>
    <div class="detail-row"><span class="detail-label">Notes</span><span class="detail-value"><%= @request.notes %></span></div>
    <div class="detail-row"><span class="detail-label">Accepted At</span><span class="detail-value"><%= @request.accepted_at&.strftime("%Y-%m-%d %H:%M") || "—" %></span></div>
    <div class="detail-row"><span class="detail-label">Expired At</span><span class="detail-value"><%= @request.expired_at&.strftime("%Y-%m-%d %H:%M") || "—" %></span></div>
    <% if @request.decline_reason.present? %>
      <div class="detail-row"><span class="detail-label">Decline Reason</span><span class="detail-value"><%= @request.decline_reason %></span></div>
    <% end %>
    <div class="detail-row"><span class="detail-label">Created At</span><span class="detail-value"><%= @request.created_at&.strftime("%Y-%m-%d %H:%M") %></span></div>
  </div>
</div>
```

Create the admin client/provider views — identical to affordance_order pattern:

`invitation_mvp/app/views/admin/clients/index.html.erb`:
```erb
<h1>Clients (<%= @total_count %>)</h1>

<table>
  <thead>
    <tr>
      <th>ID</th>
      <th>Name</th>
      <th>Email</th>
      <th>Phone</th>
      <th>Created</th>
    </tr>
  </thead>
  <tbody>
    <% @clients.each do |client| %>
      <tr>
        <td><%= link_to "##{client.id}", admin_client_path(client) %></td>
        <td><%= client.name %></td>
        <td><%= client.email %></td>
        <td><%= client.phone %></td>
        <td><%= client.created_at&.strftime("%Y-%m-%d") %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

`invitation_mvp/app/views/admin/clients/show.html.erb`:
```erb
<%= link_to "&larr; Back to Clients".html_safe, admin_clients_path, class: "back-link" %>
<h1><%= @client.name %></h1>

<div class="detail-card">
  <div class="detail-row"><span class="detail-label">Email</span><span class="detail-value"><%= @client.email %></span></div>
  <div class="detail-row"><span class="detail-label">Phone</span><span class="detail-value"><%= @client.phone %></span></div>
  <div class="detail-row"><span class="detail-label">Requests</span><span class="detail-value"><%= @client.requests.count %></span></div>
  <div class="detail-row"><span class="detail-label">Created</span><span class="detail-value"><%= @client.created_at&.strftime("%Y-%m-%d %H:%M") %></span></div>
</div>
```

`invitation_mvp/app/views/admin/providers/index.html.erb`:
```erb
<h1>Providers (<%= @total_count %>)</h1>

<table>
  <thead>
    <tr>
      <th>ID</th>
      <th>Name</th>
      <th>Email</th>
      <th>Specialization</th>
      <th>Rating</th>
      <th>Active</th>
    </tr>
  </thead>
  <tbody>
    <% @providers.each do |provider| %>
      <tr>
        <td><%= link_to "##{provider.id}", admin_provider_path(provider) %></td>
        <td><%= provider.name %></td>
        <td><%= provider.email %></td>
        <td><%= provider.specialization %></td>
        <td><%= provider.rating %></td>
        <td><%= provider.active? ? "Yes" : "No" %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

`invitation_mvp/app/views/admin/providers/show.html.erb`:
```erb
<%= link_to "&larr; Back to Providers".html_safe, admin_providers_path, class: "back-link" %>
<h1><%= @provider.name %></h1>

<div class="detail-card">
  <div class="detail-row"><span class="detail-label">Email</span><span class="detail-value"><%= @provider.email %></span></div>
  <div class="detail-row"><span class="detail-label">Phone</span><span class="detail-value"><%= @provider.phone %></span></div>
  <div class="detail-row"><span class="detail-label">Specialization</span><span class="detail-value"><%= @provider.specialization %></span></div>
  <div class="detail-row"><span class="detail-label">Rating</span><span class="detail-value"><%= @provider.rating %></span></div>
  <div class="detail-row"><span class="detail-label">Active</span><span class="detail-value"><%= @provider.active? ? "Yes" : "No" %></span></div>
  <div class="detail-row"><span class="detail-label">Requests</span><span class="detail-value"><%= @provider.requests.count %></span></div>
</div>
```

- [ ] **Step 10: Create routes**

`invitation_mvp/config/routes.rb`:
```ruby
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
```

- [ ] **Step 11: Create factories and specs**

`invitation_mvp/spec/factories/clients.rb`:
```ruby
FactoryBot.define do
  factory :client do
    sequence(:email) { |n| "client#{n}@example.com" }
    name { "Test Client" }
    phone { "+79001234567" }
    notification_preferences { { "push" => true, "sms" => true, "email" => true } }
  end
end
```

`invitation_mvp/spec/factories/providers.rb`:
```ruby
FactoryBot.define do
  factory :provider do
    sequence(:email) { |n| "provider#{n}@example.com" }
    name { "Test Provider" }
    phone { "+79007654321" }
    specialization { "cleaning" }
    active { true }
    rating { 4.5 }
    notification_preferences { { "push" => true, "sms" => true, "email" => true } }
  end
end
```

`invitation_mvp/spec/factories/cards.rb`:
```ruby
FactoryBot.define do
  factory :card do
    client
    sequence(:token) { |n| "tok_#{SecureRandom.hex(12)}_#{n}" }
    last_four { "4242" }
    brand { "visa" }
    exp_month { 12 }
    exp_year { 2028 }
    default { false }

    trait :default do
      default { true }
    end
  end
end
```

`invitation_mvp/spec/factories/requests.rb`:
```ruby
FactoryBot.define do
  factory :request do
    client
    provider
    scheduled_at { 3.days.from_now }
    duration_minutes { 120 }
    location { "123 Main St" }
    notes { "Please bring supplies" }

    trait :accepted do
      state { "accepted" }
      accepted_at { Time.current }
    end

    trait :declined do
      state { "declined" }
      decline_reason { "Not available" }
    end

    trait :expired do
      state { "expired" }
      expired_at { Time.current }
    end
  end
end
```

`invitation_mvp/spec/models/request_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Request, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:client) }
    it { is_expected.to belong_to(:provider) }
  end

  describe "validations" do
    subject { build(:request) }

    it { is_expected.to validate_presence_of(:scheduled_at) }
    it { is_expected.to validate_presence_of(:duration_minutes) }

    it "validates duration_minutes is greater than 0" do
      request = build(:request, duration_minutes: 0)
      expect(request).not_to be_valid
    end

    context "when declined" do
      it "requires decline_reason" do
        request = build(:request, :declined, decline_reason: nil)
        expect(request).not_to be_valid
      end
    end
  end

  describe "state machine" do
    let(:request) { create(:request) }

    it "has initial state of pending" do
      expect(request.state).to eq("pending")
      expect(request).to be_pending
    end

    describe "accept event" do
      it "transitions from pending to accepted" do
        request.accept!
        expect(request).to be_accepted
      end

      it "sets accepted_at timestamp" do
        freeze_time do
          request.accept!
          expect(request.reload.accepted_at).to be_within(1.second).of(Time.current)
        end
      end

      it "cannot accept from other states" do
        request.accept!
        expect { request.accept! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "decline event" do
      it "transitions from pending to declined" do
        request.update!(decline_reason: "Not available")
        request.decline!
        expect(request).to be_declined
      end

      it "cannot decline from accepted" do
        request.accept!
        expect { request.decline! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "expire event" do
      it "transitions from pending to expired" do
        request.expire!
        expect(request).to be_expired
      end

      it "sets expired_at timestamp" do
        freeze_time do
          request.expire!
          expect(request.reload.expired_at).to be_within(1.second).of(Time.current)
        end
      end
    end
  end

  describe "scopes" do
    let!(:future_request) { create(:request, scheduled_at: 1.day.from_now) }
    let!(:past_request) { create(:request, scheduled_at: 1.day.ago) }
    let!(:accepted_request) { create(:request, :accepted) }

    describe ".upcoming" do
      it "returns requests with scheduled_at in the future" do
        expect(Request.upcoming).to include(future_request)
        expect(Request.upcoming).not_to include(past_request)
      end
    end

    describe ".by_state" do
      it "filters by state" do
        expect(Request.by_state("accepted")).to include(accepted_request)
        expect(Request.by_state("accepted")).not_to include(future_request)
      end
    end
  end
end
```

`invitation_mvp/spec/services/requests/create_service_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Requests::CreateService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:valid_params) do
    {
      scheduled_at: 3.days.from_now,
      duration_minutes: 120,
      location: "123 Main St",
      notes: "Please bring supplies"
    }
  end

  subject(:result) { described_class.new(client: client, provider: provider, params: valid_params).call }

  describe "#call" do
    context "with valid params" do
      it "creates request in pending state" do
        expect(result[:success]).to be true
        expect(result[:request].state).to eq("pending")
      end

      it "notifies the provider" do
        result
        expect(read_notification_log).to include("event=request_created")
      end
    end

    context "with invalid params" do
      let(:valid_params) { { scheduled_at: nil, duration_minutes: nil } }

      it "returns errors" do
        expect(result[:success]).to be false
        expect(result[:errors]).to be_present
      end
    end
  end
end
```

`invitation_mvp/spec/services/requests/accept_service_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Requests::AcceptService do
  let(:provider) { create(:provider) }
  let(:request) { create(:request, provider: provider) }

  describe "#call" do
    context "with correct provider" do
      it "accepts the request" do
        result = described_class.new(request: request, provider: provider).call
        expect(result[:success]).to be true
        expect(request.reload).to be_accepted
      end

      it "notifies the client" do
        described_class.new(request: request, provider: provider).call
        expect(read_notification_log).to include("event=request_accepted")
      end
    end

    context "with wrong provider" do
      let(:other_provider) { create(:provider) }

      it "returns error" do
        result = described_class.new(request: request, provider: other_provider).call
        expect(result[:success]).to be false
        expect(result[:error]).to include("Not your request")
      end
    end

    context "when already accepted" do
      before { request.accept! }

      it "returns error" do
        result = described_class.new(request: request, provider: provider).call
        expect(result[:success]).to be false
      end
    end
  end
end
```

`invitation_mvp/spec/services/requests/decline_service_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Requests::DeclineService do
  let(:provider) { create(:provider) }
  let(:request) { create(:request, provider: provider) }

  describe "#call" do
    context "with correct provider and reason" do
      it "declines the request" do
        result = described_class.new(request: request, provider: provider, reason: "Not available").call
        expect(result[:success]).to be true
        expect(request.reload).to be_declined
        expect(request.decline_reason).to eq("Not available")
      end

      it "notifies the client" do
        described_class.new(request: request, provider: provider, reason: "Not available").call
        expect(read_notification_log).to include("event=request_declined")
      end
    end

    context "without reason" do
      it "returns error" do
        result = described_class.new(request: request, provider: provider, reason: nil).call
        expect(result[:success]).to be false
        expect(result[:error]).to include("Decline reason is required")
      end
    end
  end
end
```

- [ ] **Step 12: Run tests and verify**

```bash
cd /home/cutalion/code/affordance_test/invitation_mvp && bin/rails db:create db:migrate && bundle exec rspec
```

Expected: all specs pass.

- [ ] **Step 13: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add invitation_mvp/
git commit -m "feat: add invitation_mvp app (Stage 0 — clean invitation model)"
```

---

### Task 2: Create booking_clean (Stage 1 — Clean)

Fork from invitation_mvp, add Order model with full booking lifecycle.

**Files:**
- Copy: entire `invitation_mvp/` to `booking_clean/`
- Create: `app/models/order.rb`, `app/models/payment.rb`, `app/models/review.rb`
- Create: `app/services/orders/` (6 services), `app/services/payment_gateway.rb`
- Create: `app/controllers/api/orders_controller.rb`, `api/reviews_controller.rb`, `api/payments_controller.rb`
- Create: `app/controllers/admin/orders_controller.rb`, `admin/payments_controller.rb`
- Create: `app/views/admin/orders/`, `admin/payments/`
- Create: migrations for orders, payments, reviews
- Create: factories and specs for new models
- Modify: `app/models/client.rb`, `provider.rb` — add `has_many :orders`
- Modify: `app/services/requests/accept_service.rb` — create Order on accept
- Modify: `config/routes.rb`, `config/application.rb` (module name)
- Modify: admin layout, dashboard

- [ ] **Step 1: Copy and rename**

```bash
cd /home/cutalion/code/affordance_test
cp -r invitation_mvp booking_clean
```

Update `booking_clean/config/application.rb` — change module name:

```ruby
require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module BookingClean
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])
    config.api_only = true
  end
end
```

- [ ] **Step 2: Add Order migration and model**

Create `booking_clean/db/migrate/YYYYMMDDHHMMSS_create_orders.rb` (use a timestamp after existing migrations):

```ruby
class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :request, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.references :provider, null: false, foreign_key: true
      t.datetime :scheduled_at, null: false
      t.integer :duration_minutes, null: false
      t.string :location
      t.text :notes
      t.string :state, null: false, default: "pending"
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "RUB"
      t.text :cancel_reason
      t.text :reject_reason
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :orders, :state
    add_index :orders, :scheduled_at
  end
end
```

Create `booking_clean/db/migrate/YYYYMMDDHHMMSS_create_payments.rb`:

```ruby
class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :order, null: false, foreign_key: true
      t.references :card, null: true, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "RUB"
      t.integer :fee_cents, null: false, default: 0
      t.string :status, null: false, default: "pending"
      t.datetime :held_at
      t.datetime :charged_at
      t.datetime :refunded_at

      t.timestamps
    end

    add_index :payments, :status
  end
end
```

Create `booking_clean/db/migrate/YYYYMMDDHHMMSS_create_reviews.rb`:

```ruby
class CreateReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :reviews do |t|
      t.references :order, null: false, foreign_key: true
      t.string :author_type, null: false
      t.integer :author_id, null: false
      t.integer :rating, null: false
      t.text :body

      t.timestamps
    end

    add_index :reviews, [:author_type, :author_id]
    add_index :reviews, [:order_id, :author_type, :author_id], unique: true
  end
end
```

`booking_clean/app/models/order.rb`:
```ruby
class Order < ApplicationRecord
  include AASM
  include Paginatable

  belongs_to :request, optional: true
  belongs_to :client
  belongs_to :provider
  has_one :payment, dependent: :destroy
  has_many :reviews, dependent: :destroy

  validates :scheduled_at, presence: true
  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :cancel_reason, presence: true, if: -> { canceled? }
  validates :reject_reason, presence: true, if: -> { rejected? }

  scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
  scope :past, -> { where("scheduled_at <= ?", Time.current) }
  scope :by_state, ->(state) { where(state: state) if state.present? }
  scope :by_client, ->(client_id) { where(client_id: client_id) if client_id.present? }
  scope :by_provider, ->(provider_id) { where(provider_id: provider_id) if provider_id.present? }
  scope :scheduled_between, ->(from, to) {
    scope = all
    scope = scope.where("scheduled_at >= ?", from) if from.present?
    scope = scope.where("scheduled_at <= ?", to) if to.present?
    scope
  }
  scope :sorted, -> { order(scheduled_at: :desc) }

  aasm column: :state do
    state :pending, initial: true
    state :confirmed
    state :in_progress
    state :completed
    state :canceled
    state :rejected

    event :confirm do
      transitions from: :pending, to: :confirmed
    end

    event :start do
      transitions from: :confirmed, to: :in_progress
      after do
        update!(started_at: Time.current)
      end
    end

    event :complete do
      transitions from: :in_progress, to: :completed
      after do
        update!(completed_at: Time.current)
      end
    end

    event :cancel do
      transitions from: [:pending, :confirmed], to: :canceled
    end

    event :reject do
      transitions from: [:confirmed, :in_progress], to: :rejected
    end
  end
end
```

`booking_clean/app/models/payment.rb` — identical to affordance_order/app/models/payment.rb (see Step 2 of Task 1 context — already read above).

`booking_clean/app/models/review.rb` — identical to affordance_order/app/models/review.rb.

Modify `booking_clean/app/models/client.rb` — add:
```ruby
has_many :orders, dependent: :destroy
has_many :reviews, as: :author, dependent: :destroy
```

Modify `booking_clean/app/models/provider.rb` — add:
```ruby
has_many :orders, dependent: :destroy
has_many :reviews, as: :author, dependent: :destroy
```

Modify `booking_clean/app/models/request.rb` — add association:
```ruby
has_one :order, dependent: :destroy
```

- [ ] **Step 3: Add Order services**

Create all 6 Order services — identical to the affordance_order services already read. Copy them exactly:
- `booking_clean/app/services/orders/create_service.rb`
- `booking_clean/app/services/orders/confirm_service.rb`
- `booking_clean/app/services/orders/start_service.rb`
- `booking_clean/app/services/orders/complete_service.rb`
- `booking_clean/app/services/orders/cancel_service.rb`
- `booking_clean/app/services/orders/reject_service.rb`

Copy `booking_clean/app/services/payment_gateway.rb` — identical to affordance_order.

Modify `booking_clean/app/services/requests/accept_service.rb` — create Order on accept:

```ruby
module Requests
  class AcceptService
    def initialize(request:, provider:)
      @request = request
      @provider = provider
    end

    def call
      return error("Not your request") unless @request.provider_id == @provider.id

      Request.transaction do
        @request.accept!

        order_result = Orders::CreateService.new(
          client: @request.client,
          provider: @request.provider,
          params: {
            scheduled_at: @request.scheduled_at,
            duration_minutes: @request.duration_minutes,
            location: @request.location,
            notes: @request.notes,
            amount_cents: @request.client.default_card ? 350_000 : 350_000,
            currency: "RUB"
          },
          request: @request
        ).call

        unless order_result[:success]
          raise ActiveRecord::Rollback
          return error("Failed to create order")
        end
      end

      NotificationService.notify(@request.client, :request_accepted, request_id: @request.id)
      { success: true, request: @request }
    rescue AASM::InvalidTransition
      error("Cannot accept request in #{@request.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

Update `Orders::CreateService` to accept optional `request:` parameter:

```ruby
module Orders
  class CreateService
    def initialize(client:, provider:, params:, request: nil)
      @client = client
      @provider = provider
      @params = params
      @request = request
    end

    def call
      order = Order.new(
        request: @request,
        client: @client,
        provider: @provider,
        scheduled_at: @params[:scheduled_at],
        duration_minutes: @params[:duration_minutes],
        location: @params[:location],
        notes: @params[:notes],
        amount_cents: @params[:amount_cents],
        currency: @params[:currency] || "RUB"
      )

      Order.transaction do
        order.save!
        Payment.create!(
          order: order,
          amount_cents: order.amount_cents,
          currency: order.currency,
          fee_cents: calculate_fee(order.amount_cents),
          status: "pending"
        )
      end

      NotificationService.notify(@provider, :order_created, order_id: order.id)
      { success: true, order: order }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, errors: e.record.errors }
    end

    private

    def calculate_fee(amount_cents)
      (amount_cents * 0.1).to_i
    end
  end
end
```

- [ ] **Step 4: Add Order API controllers, routes, admin views**

Copy from affordance_order (already read): `api/orders_controller.rb`, `api/reviews_controller.rb`, `api/payments_controller.rb`, `admin/orders_controller.rb`, `admin/payments_controller.rb`, and all corresponding admin views.

Update `booking_clean/config/routes.rb`:

```ruby
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
  end

  namespace :admin do
    get "/", to: "dashboard#index"
    get "dashboard", to: "dashboard#index"
    resources :requests, only: [:index, :show]
    resources :orders, only: [:index, :show]
    resources :clients, only: [:index, :show]
    resources :providers, only: [:index, :show]
    resources :payments, only: [:index, :show]
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
```

Update admin layout to add Orders and Payments nav links. Update dashboard to include order stats.

- [ ] **Step 5: Add factories, specs, run tests**

Add factories for orders, payments, reviews (identical to affordance_order). Add Order model spec and service specs.

```bash
cd /home/cutalion/code/affordance_test/booking_clean
rm -f db/schema.rb && bin/rails db:create db:migrate && bundle exec rspec
```

Expected: all specs pass.

- [ ] **Step 6: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add booking_clean/
git commit -m "feat: add booking_clean app (Stage 1 Clean — Request + Order)"
```

---

### Task 3: Create booking_debt (Stage 1 — Debt)

Fork from invitation_mvp. Extend Request with booking lifecycle (payments, cancellation, reviews) WITHOUT adding an Order model.

**Key debt:** `AcceptService` captures payment. `accepted` means "paid and confirmed." Reviews belong to Request.

- [ ] **Step 1: Copy from invitation_mvp**

```bash
cd /home/cutalion/code/affordance_test
cp -r invitation_mvp booking_debt
```

Update `booking_debt/config/application.rb` — module `BookingDebt`.

- [ ] **Step 2: Extend Request migration and model**

Replace `booking_debt/db/migrate/xxx_create_requests.rb` with extended version:

```ruby
class CreateRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :requests do |t|
      t.references :client, null: false, foreign_key: true
      t.references :provider, null: false, foreign_key: true
      t.datetime :scheduled_at, null: false
      t.integer :duration_minutes, null: false
      t.string :location
      t.text :notes
      t.string :state, null: false, default: "pending"
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "RUB"
      t.text :decline_reason
      t.text :cancel_reason
      t.text :reject_reason
      t.datetime :accepted_at
      t.datetime :expired_at
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :requests, :state
    add_index :requests, :scheduled_at
  end
end
```

Add payments and reviews migrations (same as booking_clean but referencing :request instead of :order):

`booking_debt/db/migrate/YYYYMMDDHHMMSS_create_payments.rb`:
```ruby
class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :request, null: false, foreign_key: true
      t.references :card, null: true, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "RUB"
      t.integer :fee_cents, null: false, default: 0
      t.string :status, null: false, default: "pending"
      t.datetime :held_at
      t.datetime :charged_at
      t.datetime :refunded_at

      t.timestamps
    end

    add_index :payments, :status
  end
end
```

`booking_debt/db/migrate/YYYYMMDDHHMMSS_create_reviews.rb`:
```ruby
class CreateReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :reviews do |t|
      t.references :request, null: false, foreign_key: true
      t.string :author_type, null: false
      t.integer :author_id, null: false
      t.integer :rating, null: false
      t.text :body

      t.timestamps
    end

    add_index :reviews, [:author_type, :author_id]
    add_index :reviews, [:request_id, :author_type, :author_id], unique: true
  end
end
```

Replace `booking_debt/app/models/request.rb`:

```ruby
class Request < ApplicationRecord
  include AASM
  include Paginatable

  belongs_to :client
  belongs_to :provider
  has_one :payment, dependent: :destroy
  has_many :reviews, dependent: :destroy

  validates :scheduled_at, presence: true
  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :decline_reason, presence: true, if: -> { declined? }
  validates :cancel_reason, presence: true, if: -> { canceled? }
  validates :reject_reason, presence: true, if: -> { rejected? }

  scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
  scope :past, -> { where("scheduled_at <= ?", Time.current) }
  scope :by_state, ->(state) { where(state: state) if state.present? }
  scope :by_client, ->(client_id) { where(client_id: client_id) if client_id.present? }
  scope :by_provider, ->(provider_id) { where(provider_id: provider_id) if provider_id.present? }
  scope :scheduled_between, ->(from, to) {
    scope = all
    scope = scope.where("scheduled_at >= ?", from) if from.present?
    scope = scope.where("scheduled_at <= ?", to) if to.present?
    scope
  }
  scope :sorted, -> { order(scheduled_at: :desc) }

  aasm column: :state do
    state :pending, initial: true
    state :accepted
    state :in_progress
    state :completed
    state :declined
    state :expired
    state :canceled
    state :rejected

    event :accept do
      transitions from: :pending, to: :accepted
      after do
        update!(accepted_at: Time.current)
      end
    end

    event :decline do
      transitions from: :pending, to: :declined
    end

    event :expire do
      transitions from: :pending, to: :expired
      after do
        update!(expired_at: Time.current)
      end
    end

    event :start do
      transitions from: :accepted, to: :in_progress
      after do
        update!(started_at: Time.current)
      end
    end

    event :complete do
      transitions from: :in_progress, to: :completed
      after do
        update!(completed_at: Time.current)
      end
    end

    event :cancel do
      transitions from: [:pending, :accepted], to: :canceled
    end

    event :reject do
      transitions from: [:accepted, :in_progress], to: :rejected
    end
  end
end
```

Add `booking_debt/app/models/payment.rb` (belongs_to :request):

```ruby
class Payment < ApplicationRecord
  belongs_to :request
  belongs_to :card, optional: true

  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending held charged refunded] }

  scope :by_status, ->(status) { where(status: status) if status.present? }

  def hold!
    update!(status: "held", held_at: Time.current)
  end

  def charge!
    update!(status: "charged", charged_at: Time.current)
  end

  def refund!
    update!(status: "refunded", refunded_at: Time.current)
  end
end
```

Add `booking_debt/app/models/review.rb` (belongs_to :request):

```ruby
class Review < ApplicationRecord
  belongs_to :request
  belongs_to :author, polymorphic: true

  validates :rating, presence: true, numericality: { in: 1..5 }
  validates :author_type, inclusion: { in: %w[Client Provider] }
  validates :request_id, uniqueness: { scope: [:author_type, :author_id], message: "already reviewed by this author" }
  validate :request_must_be_completed

  private

  def request_must_be_completed
    return if request.nil?
    unless request.completed?
      errors.add(:request, "must be completed before reviewing")
    end
  end
end
```

- [ ] **Step 3: Add services — the debt is here**

Replace `booking_debt/app/services/requests/accept_service.rb` — **this is where the debt lives**: accept now captures payment:

```ruby
module Requests
  class AcceptService
    def initialize(request:, provider:)
      @request = request
      @provider = provider
    end

    def call
      return error("Not your request") unless @request.provider_id == @provider.id

      Request.transaction do
        @request.accept!

        Payment.create!(
          request: @request,
          amount_cents: @request.amount_cents,
          currency: @request.currency,
          fee_cents: calculate_fee(@request.amount_cents),
          status: "pending"
        )
      end

      PaymentGateway.hold(@request.payment) if @request.client.default_card

      NotificationService.notify(@request.client, :request_accepted, request_id: @request.id)
      { success: true, request: @request }
    rescue AASM::InvalidTransition
      error("Cannot accept request in #{@request.state} state")
    end

    private

    def calculate_fee(amount_cents)
      (amount_cents * 0.1).to_i
    end

    def error(message)
      { success: false, error: message }
    end
  end
end
```

Add lifecycle services:

`booking_debt/app/services/requests/start_service.rb`:
```ruby
module Requests
  class StartService
    def initialize(request:, provider:)
      @request = request
      @provider = provider
    end

    def call
      return error("Not your request") unless @request.provider_id == @provider.id

      @request.start!
      NotificationService.notify(@request.client, :request_started, request_id: @request.id)
      { success: true, request: @request }
    rescue AASM::InvalidTransition
      error("Cannot start request in #{@request.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

`booking_debt/app/services/requests/complete_service.rb`:
```ruby
module Requests
  class CompleteService
    def initialize(request:, provider:)
      @request = request
      @provider = provider
    end

    def call
      return error("Not your request") unless @request.provider_id == @provider.id

      @request.complete!

      if @request.payment&.status == "held"
        PaymentGateway.charge(@request.payment)
      end

      NotificationService.notify(@request.client, :request_completed, request_id: @request.id)
      NotificationService.notify(@request.provider, :request_completed, request_id: @request.id)
      { success: true, request: @request }
    rescue AASM::InvalidTransition
      error("Cannot complete request in #{@request.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

`booking_debt/app/services/requests/cancel_service.rb`:
```ruby
module Requests
  class CancelService
    def initialize(request:, client:, reason:)
      @request = request
      @client = client
      @reason = reason
    end

    def call
      return error("Not your request") unless @request.client_id == @client.id
      return error("Cancel reason is required") if @reason.blank?

      @request.cancel_reason = @reason
      @request.cancel!

      if @request.payment && %w[held charged].include?(@request.payment.status)
        PaymentGateway.refund(@request.payment)
      end

      NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
      { success: true, request: @request }
    rescue AASM::InvalidTransition
      error("Cannot cancel request in #{@request.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

`booking_debt/app/services/requests/reject_service.rb`:
```ruby
module Requests
  class RejectService
    def initialize(request:, provider:, reason:)
      @request = request
      @provider = provider
      @reason = reason
    end

    def call
      return error("Not your request") unless @request.provider_id == @provider.id
      return error("Reject reason is required") if @reason.blank?

      @request.reject_reason = @reason
      @request.reject!

      if @request.payment && %w[held charged].include?(@request.payment.status)
        PaymentGateway.refund(@request.payment)
      end

      NotificationService.notify(@request.client, :request_rejected, request_id: @request.id)
      { success: true, request: @request }
    rescue AASM::InvalidTransition
      error("Cannot reject request in #{@request.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

Add `booking_debt/app/services/payment_gateway.rb` — same as affordance_order but references `@payment.request` instead of `@payment.order`:

```ruby
class PaymentGateway
  LOG_PATH = -> { Rails.root.join("log/payments.log") }

  def self.hold(payment)
    new(payment).hold
  end

  def self.charge(payment)
    new(payment).charge
  end

  def self.refund(payment)
    new(payment).refund
  end

  def initialize(payment)
    @payment = payment
  end

  def hold
    card = @payment.request.client.default_card
    return { success: false, error: "No default card" } unless card

    @payment.update!(card: card)
    @payment.hold!
    log("hold", "payment_id=#{@payment.id} amount=#{@payment.amount_cents} card=*#{card.last_four}")
    { success: true }
  end

  def charge
    return { success: false, error: "Payment not held" } unless @payment.status == "held"

    @payment.charge!
    log("charge", "payment_id=#{@payment.id} amount=#{@payment.amount_cents} card=*#{@payment.card.last_four}")
    { success: true }
  end

  def refund
    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)

    @payment.refund!
    log("refund", "payment_id=#{@payment.id} amount=#{@payment.amount_cents}")
    { success: true }
  end

  private

  def log(action, message)
    File.open(self.class::LOG_PATH.call, "a") do |f|
      f.puts "[PAYMENT] action=#{action} #{message} at=#{Time.current.iso8601}"
    end
  end
end
```

- [ ] **Step 4: Extend Request controller with lifecycle actions**

Replace `booking_debt/app/controllers/api/requests_controller.rb` — add start, complete, cancel, reject actions (same pattern as affordance_order's orders_controller but using Request services).

Add `api/reviews_controller.rb` and `api/payments_controller.rb` — same pattern but referencing `request` instead of `order`.

Update routes, admin layout, dashboard, admin views for payments. Update the request detail JSON to include payment, amount, and lifecycle timestamps.

- [ ] **Step 5: Update factories, add specs, run tests**

Update request factory with `:in_progress`, `:completed`, `:canceled`, `:rejected` traits plus `:with_payment`. Add payment and review factories referencing request.

```bash
cd /home/cutalion/code/affordance_test/booking_debt
rm -f db/schema.rb && bin/rails db:create db:migrate && bundle exec rspec
```

- [ ] **Step 6: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add booking_debt/
git commit -m "feat: add booking_debt app (Stage 1 Debt — Request absorbs booking lifecycle)"
```

---

### Task 4: Create marketplace_clean (Stage 2 — Clean)

Fork from booking_clean, add Announcement and Response models.

- [ ] **Step 1: Copy**

```bash
cp -r booking_clean marketplace_clean
```

Update module name to `MarketplaceClean`.

- [ ] **Step 2: Add Announcement and Response migrations + models**

`marketplace_clean/db/migrate/YYYYMMDDHHMMSS_create_announcements.rb`:
```ruby
class CreateAnnouncements < ActiveRecord::Migration[8.1]
  def change
    create_table :announcements do |t|
      t.references :client, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :location
      t.datetime :scheduled_at
      t.integer :duration_minutes
      t.integer :budget_cents
      t.string :currency, null: false, default: "RUB"
      t.string :state, null: false, default: "draft"
      t.datetime :published_at
      t.datetime :closed_at

      t.timestamps
    end

    add_index :announcements, :state
  end
end
```

`marketplace_clean/db/migrate/YYYYMMDDHHMMSS_create_responses.rb`:
```ruby
class CreateResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :responses do |t|
      t.references :announcement, null: false, foreign_key: true
      t.references :provider, null: false, foreign_key: true
      t.text :message
      t.integer :proposed_amount_cents
      t.string :state, null: false, default: "pending"

      t.timestamps
    end

    add_index :responses, :state
    add_index :responses, [:announcement_id, :provider_id], unique: true
  end
end
```

`marketplace_clean/app/models/announcement.rb`:
```ruby
class Announcement < ApplicationRecord
  include AASM
  include Paginatable

  belongs_to :client
  has_many :responses, dependent: :destroy

  validates :title, presence: true
  validates :currency, presence: true

  scope :by_state, ->(state) { where(state: state) if state.present? }
  scope :sorted, -> { order(created_at: :desc) }

  aasm column: :state do
    state :draft, initial: true
    state :published
    state :closed

    event :publish do
      transitions from: :draft, to: :published
      after do
        update!(published_at: Time.current)
      end
    end

    event :close do
      transitions from: :published, to: :closed
      after do
        update!(closed_at: Time.current)
      end
    end
  end
end
```

`marketplace_clean/app/models/response.rb`:
```ruby
class Response < ApplicationRecord
  include AASM

  belongs_to :announcement
  belongs_to :provider

  validates :announcement_id, uniqueness: { scope: :provider_id, message: "already responded" }

  aasm column: :state do
    state :pending, initial: true
    state :selected
    state :rejected

    event :select do
      transitions from: :pending, to: :selected
    end

    event :reject do
      transitions from: :pending, to: :rejected
    end
  end
end
```

Add associations to client and provider models: `has_many :announcements`, `has_many :responses`.

- [ ] **Step 3: Add Announcement and Response services**

`marketplace_clean/app/services/announcements/create_service.rb`:
```ruby
module Announcements
  class CreateService
    def initialize(client:, params:)
      @client = client
      @params = params
    end

    def call
      announcement = Announcement.new(
        client: @client,
        title: @params[:title],
        description: @params[:description],
        location: @params[:location],
        scheduled_at: @params[:scheduled_at],
        duration_minutes: @params[:duration_minutes],
        budget_cents: @params[:budget_cents],
        currency: @params[:currency] || "RUB"
      )

      announcement.save!
      { success: true, announcement: announcement }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, errors: e.record.errors }
    end
  end
end
```

`marketplace_clean/app/services/announcements/publish_service.rb`:
```ruby
module Announcements
  class PublishService
    def initialize(announcement:, client:)
      @announcement = announcement
      @client = client
    end

    def call
      return error("Not your announcement") unless @announcement.client_id == @client.id

      @announcement.publish!
      { success: true, announcement: @announcement }
    rescue AASM::InvalidTransition
      error("Cannot publish announcement in #{@announcement.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

`marketplace_clean/app/services/announcements/close_service.rb`:
```ruby
module Announcements
  class CloseService
    def initialize(announcement:, client:)
      @announcement = announcement
      @client = client
    end

    def call
      return error("Not your announcement") unless @announcement.client_id == @client.id

      @announcement.close!
      { success: true, announcement: @announcement }
    rescue AASM::InvalidTransition
      error("Cannot close announcement in #{@announcement.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

`marketplace_clean/app/services/responses/create_service.rb`:
```ruby
module Responses
  class CreateService
    def initialize(announcement:, provider:, params:)
      @announcement = announcement
      @provider = provider
      @params = params
    end

    def call
      return error("Announcement not published") unless @announcement.published?

      response = @announcement.responses.new(
        provider: @provider,
        message: @params[:message],
        proposed_amount_cents: @params[:proposed_amount_cents]
      )

      response.save!
      NotificationService.notify(@announcement.client, :response_received, announcement_id: @announcement.id)
      { success: true, response: response }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, errors: e.record.errors }
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

`marketplace_clean/app/services/responses/select_service.rb`:
```ruby
module Responses
  class SelectService
    def initialize(response:, client:)
      @response = response
      @client = client
      @announcement = response.announcement
    end

    def call
      return error("Not your announcement") unless @announcement.client_id == @client.id

      Response.transaction do
        @response.select!

        # Reject all other pending responses
        @announcement.responses.where.not(id: @response.id).where(state: "pending").find_each do |r|
          r.reject!
        end

        # Create an order from the selected response
        Orders::CreateService.new(
          client: @announcement.client,
          provider: @response.provider,
          params: {
            scheduled_at: @announcement.scheduled_at || 3.days.from_now,
            duration_minutes: @announcement.duration_minutes || 120,
            location: @announcement.location,
            notes: "From announcement: #{@announcement.title}",
            amount_cents: @response.proposed_amount_cents || @announcement.budget_cents || 0,
            currency: @announcement.currency
          }
        ).call

        @announcement.close!
      end

      NotificationService.notify(@response.provider, :response_selected, announcement_id: @announcement.id)
      { success: true, response: @response }
    rescue AASM::InvalidTransition
      error("Cannot select response in #{@response.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

`marketplace_clean/app/services/responses/reject_service.rb`:
```ruby
module Responses
  class RejectService
    def initialize(response:, client:)
      @response = response
      @client = client
    end

    def call
      return error("Not your announcement") unless @response.announcement.client_id == @client.id

      @response.reject!
      NotificationService.notify(@response.provider, :response_rejected, announcement_id: @response.announcement_id)
      { success: true, response: @response }
    rescue AASM::InvalidTransition
      error("Cannot reject response in #{@response.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

- [ ] **Step 4: Add controllers, routes, admin views for announcements + responses**

Add `api/announcements_controller.rb`, `api/responses_controller.rb`, `admin/announcements_controller.rb`. Add admin views for announcements. Update routes, layout, dashboard.

- [ ] **Step 5: Add factories, specs, run tests**

```bash
cd /home/cutalion/code/affordance_test/marketplace_clean
rm -f db/schema.rb && bin/rails db:create db:migrate && bundle exec rspec
```

- [ ] **Step 6: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add marketplace_clean/
git commit -m "feat: add marketplace_clean app (Stage 2 Clean — Request + Order + Announcement + Response)"
```

---

### Task 5: Create marketplace_debt (Stage 2 — Debt / God Object)

Fork from booking_debt. Add Announcement model. Announcement responses are Requests. `AcceptService` now serves three purposes.

- [ ] **Step 1: Copy**

```bash
cp -r booking_debt marketplace_debt
```

Update module name to `MarketplaceDebt`.

- [ ] **Step 2: Add Announcement model + extend Request**

`marketplace_debt/db/migrate/YYYYMMDDHHMMSS_create_announcements.rb` — same as marketplace_clean.

`marketplace_debt/db/migrate/YYYYMMDDHHMMSS_add_announcement_to_requests.rb`:
```ruby
class AddAnnouncementToRequests < ActiveRecord::Migration[8.1]
  def change
    add_reference :requests, :announcement, null: true, foreign_key: true
    add_column :requests, :response_message, :text
    add_column :requests, :proposed_amount_cents, :integer
  end
end
```

`marketplace_debt/app/models/announcement.rb`:
```ruby
class Announcement < ApplicationRecord
  include AASM
  include Paginatable

  belongs_to :client
  has_many :requests, dependent: :destroy

  validates :title, presence: true
  validates :currency, presence: true

  scope :by_state, ->(state) { where(state: state) if state.present? }
  scope :sorted, -> { order(created_at: :desc) }

  aasm column: :state do
    state :draft, initial: true
    state :published
    state :closed

    event :publish do
      transitions from: :draft, to: :published
      after do
        update!(published_at: Time.current)
      end
    end

    event :close do
      transitions from: :published, to: :closed
      after do
        update!(closed_at: Time.current)
      end
    end
  end
end
```

Modify `marketplace_debt/app/models/request.rb` — add:
```ruby
belongs_to :announcement, optional: true
```

Modify `marketplace_debt/app/models/client.rb` — add:
```ruby
has_many :announcements, dependent: :destroy
```

- [ ] **Step 3: Modify AcceptService — the god service**

Replace `marketplace_debt/app/services/requests/accept_service.rb`:

```ruby
module Requests
  class AcceptService
    def initialize(request:, actor:)
      @request = request
      @actor = actor
    end

    def call
      if @request.announcement.present?
        # Announcement response flow: client selects a provider's response
        return error("Not your announcement") unless @request.announcement.client_id == @actor.id
        accept_announcement_response!
      else
        # Direct invitation flow: provider accepts client's request
        return error("Not your request") unless @request.provider_id == @actor.id
        accept_invitation!
      end
    rescue AASM::InvalidTransition
      error("Cannot accept request in #{@request.state} state")
    end

    private

    def accept_invitation!
      Request.transaction do
        @request.accept!

        Payment.create!(
          request: @request,
          amount_cents: @request.amount_cents,
          currency: @request.currency,
          fee_cents: calculate_fee(@request.amount_cents),
          status: "pending"
        )
      end

      PaymentGateway.hold(@request.payment) if @request.client.default_card

      NotificationService.notify(@request.client, :request_accepted, request_id: @request.id)
      { success: true, request: @request }
    end

    def accept_announcement_response!
      Request.transaction do
        @request.accept!

        amount = @request.proposed_amount_cents || @request.announcement.budget_cents || 0
        Payment.create!(
          request: @request,
          amount_cents: amount,
          currency: @request.currency,
          fee_cents: calculate_fee(amount),
          status: "pending"
        )

        # Decline all other pending responses to this announcement
        @request.announcement.requests
          .where.not(id: @request.id)
          .where(state: "pending")
          .find_each do |r|
            r.decline_reason = "Another provider was selected"
            r.decline!
          end

        @request.announcement.close!
      end

      PaymentGateway.hold(@request.payment) if @request.client.default_card

      NotificationService.notify(@request.provider, :request_accepted, request_id: @request.id)
      { success: true, request: @request }
    end

    def calculate_fee(amount_cents)
      (amount_cents * 0.1).to_i
    end

    def error(message)
      { success: false, error: message }
    end
  end
end
```

- [ ] **Step 4: Add Announcement controller and views**

`marketplace_debt/app/controllers/api/announcements_controller.rb`:
```ruby
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
```

Update routes to add announcement endpoints and the `respond` action. Update admin layout and dashboard.

- [ ] **Step 5: Add factories, specs, run tests**

```bash
cd /home/cutalion/code/affordance_test/marketplace_debt
rm -f db/schema.rb && bin/rails db:create db:migrate && bundle exec rspec
```

- [ ] **Step 6: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add marketplace_debt/
git commit -m "feat: add marketplace_debt app (Stage 2 Debt — Request is god object)"
```

---

### Task 6: Create experiment infrastructure

**Files:**
- Create: `experiments_debt/run.sh`
- Create: `experiments_debt/analyze.sh`
- Create: `experiments_debt/e01-describe-system/prompt.md`, `config.sh`
- Create: `experiments_debt/e02-happy-path/prompt.md`, `config.sh`
- Create: `experiments_debt/e03-counter-proposal/prompt.md`, `config.sh`
- Create: `experiments_debt/e04-cancellation-fee/prompt.md`, `config.sh`
- Create: `experiments_debt/e05-recurring-bookings/prompt.md`, `config.sh`
- Create: `experiments_debt/e06-withdraw-response/prompt.md`, `config.sh`

- [ ] **Step 1: Create experiment directories and prompts**

```bash
mkdir -p experiments_debt/{e01-describe-system,e02-happy-path,e03-counter-proposal,e04-cancellation-fee,e05-recurring-bookings,e06-withdraw-response}/runs
```

`experiments_debt/e01-describe-system/prompt.md`:
```
Describe what this system does. What is the domain, what are the main entities, and what is the typical workflow?
```

`experiments_debt/e01-describe-system/config.sh`:
```bash
TYPE=readonly
```

`experiments_debt/e02-happy-path/prompt.md`:
```
What is the happy path for the main entity in this system? Walk through it step by step.
```

`experiments_debt/e02-happy-path/config.sh`:
```bash
TYPE=readonly
```

`experiments_debt/e03-counter-proposal/prompt.md`:
```
Add the ability for providers to propose a different time for a booking. The client can accept or decline the counter-proposal. Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation.
```

`experiments_debt/e03-counter-proposal/config.sh`:
```bash
TYPE=code
```

`experiments_debt/e04-cancellation-fee/prompt.md`:
```
Add a cancellation fee: if a booking is canceled within 24 hours of the scheduled time, charge the client 50% of the booking amount. Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation.
```

`experiments_debt/e04-cancellation-fee/config.sh`:
```bash
TYPE=code
```

`experiments_debt/e05-recurring-bookings/prompt.md`:
```
Add the ability to create recurring weekly bookings — 5 sessions with the same provider at the same time. Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation.
```

`experiments_debt/e05-recurring-bookings/config.sh`:
```bash
TYPE=code
```

`experiments_debt/e06-withdraw-response/prompt.md`:
```
Add the ability for a provider to withdraw their response to an announcement before the client makes a decision. Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation.
```

`experiments_debt/e06-withdraw-response/config.sh`:
```bash
TYPE=code
```

- [ ] **Step 2: Create run.sh**

`experiments_debt/run.sh`:
```bash
#!/bin/bash
set -euo pipefail

# Experiment runner for debt threshold test
# Usage: ./experiments_debt/run.sh [experiment] [app] [max_run]
# Opus only. All arguments optional.

unset ANTHROPIC_API_KEY

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS="${1:-e01-describe-system e02-happy-path e03-counter-proposal e04-cancellation-fee e05-recurring-bookings e06-withdraw-response}"
MODEL="opus"
APPS="${2:-invitation_mvp booking_clean booking_debt marketplace_clean marketplace_debt}"
MAX_RUN="${3:-3}"

# Define which experiments run on which apps
can_run() {
  local exp="$1" app="$2"
  case "$exp" in
    e01-describe-system|e02-happy-path)
      return 0 ;; # All apps
    e03-counter-proposal|e04-cancellation-fee|e05-recurring-bookings)
      case "$app" in
        invitation_mvp) return 1 ;; # Skip MVP for these
        *) return 0 ;;
      esac ;;
    e06-withdraw-response)
      case "$app" in
        marketplace_clean|marketplace_debt) return 0 ;;
        *) return 1 ;; # Only stage 2 apps
      esac ;;
  esac
}

TOTAL=0
CURRENT=0
DONE=0
SKIPPED=0
FAILED=0
WALL_START=$(date +%s)

for exp in $EXPERIMENTS; do
  for app in $APPS; do
    can_run "$exp" "$app" || continue
    for run in $(seq 1 "$MAX_RUN"); do
      TOTAL=$((TOTAL + 1))
    done
  done
done

# Hide CLAUDE.md
if [ -f "$ROOT/CLAUDE.md" ]; then
  mv "$ROOT/CLAUDE.md" "$ROOT/.CLAUDE.md.hidden"
  trap 'mv "$ROOT/.CLAUDE.md.hidden" "$ROOT/CLAUDE.md" 2>/dev/null || true' EXIT
fi

echo "=== Debt Threshold Experiment Runner ==="
echo "Experiments: $EXPERIMENTS"
echo "Model: $MODEL"
echo "Apps: $APPS"
echo "Runs per combo: $MAX_RUN"
echo "Total invocations: $TOTAL"
echo "========================================"
echo ""

for exp in $EXPERIMENTS; do
  source "$ROOT/experiments_debt/$exp/config.sh"
  PROMPT=$(cat "$ROOT/experiments_debt/$exp/prompt.md")

  echo "--- Experiment: $exp (type=$TYPE) ---"

  for app in $APPS; do
    can_run "$exp" "$app" || continue

    APP_DIR="$ROOT/$app"

    for run in $(seq 1 "$MAX_RUN"); do
      OUTPUT_FILE="$ROOT/experiments_debt/$exp/runs/${app}-${MODEL}-${run}.md"
      RUN_LABEL="$exp/$app/$MODEL/run-$run"

      CURRENT=$((CURRENT + 1))

      if [ -f "$OUTPUT_FILE" ]; then
        SKIPPED=$((SKIPPED + 1))
        echo "  [$CURRENT/$TOTAL] SKIP $RUN_LABEL (exists)"
        continue
      fi

      echo -n "  [$CURRENT/$TOTAL] RUN  $RUN_LABEL ... "
      START_TIME=$(date +%s)

      if [ "$TYPE" = "code" ]; then
        BRANCH="debt_experiment/${exp}/${app}/${MODEL}/run-${run}"

        cd "$ROOT"
        git checkout main 2>/dev/null
        git branch -D "$BRANCH" 2>/dev/null || true
        git checkout -b "$BRANCH" 2>/dev/null

        cd "$APP_DIR"
        RESULT=$(echo "$PROMPT" | claude -p --dangerously-skip-permissions --disable-slash-commands --model "$MODEL" 2>/dev/null) || true

        cd "$ROOT"
        git add "$app/" 2>/dev/null || true
        git diff --cached --quiet 2>/dev/null || git commit -m "experiment: $exp $app $MODEL run-$run (auto-committed)" 2>/dev/null || true

        DIFF=$(git diff main..HEAD -- "$app/" 2>/dev/null) || DIFF="(no diff)"

        {
          echo "# Experiment: $exp"
          echo "# App: $app | Model: $MODEL | Run: $run"
          echo "# Branch: $BRANCH"
          echo ""
          echo "---"
          echo ""
          echo "## Claude Output"
          echo ""
          echo "$RESULT"
          echo ""
          echo "---"
          echo ""
          echo "## Git Diff"
          echo ""
          echo '```diff'
          echo "$DIFF"
          echo '```'
        } > "$OUTPUT_FILE"

        git checkout main 2>/dev/null

      else
        cd "$APP_DIR"
        RESULT=$(echo "$PROMPT" | claude -p --dangerously-skip-permissions --disable-slash-commands --model "$MODEL" 2>/dev/null) || true
        cd "$ROOT"

        {
          echo "# Experiment: $exp"
          echo "# App: $app | Model: $MODEL | Run: $run"
          echo ""
          echo "---"
          echo ""
          echo "$RESULT"
        } > "$OUTPUT_FILE"
      fi

      END_TIME=$(date +%s)
      ELAPSED=$((END_TIME - START_TIME))

      if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
        DONE=$((DONE + 1))
        echo "done (${ELAPSED}s)"
      else
        FAILED=$((FAILED + 1))
        echo "FAILED (${ELAPSED}s)"
      fi
    done
  done
  echo ""
done

WALL_END=$(date +%s)
WALL_ELAPSED=$(( WALL_END - WALL_START ))
WALL_MIN=$(( WALL_ELAPSED / 60 ))
WALL_SEC=$(( WALL_ELAPSED % 60 ))

echo "========================================"
echo "Complete: $DONE | Skipped: $SKIPPED | Failed: $FAILED | Total: $TOTAL"
echo "Wall time: ${WALL_MIN}m ${WALL_SEC}s"
echo "========================================"
```

```bash
chmod +x experiments_debt/run.sh
```

- [ ] **Step 3: Create analyze.sh**

`experiments_debt/analyze.sh` — adapted from the existing analyze.sh. Labels apps as App A through E. Uses blind comparison. Generates summaries that reveal app identities.

```bash
#!/bin/bash
set -euo pipefail

unset ANTHROPIC_API_KEY

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS="${1:-e01-describe-system e02-happy-path e03-counter-proposal e04-cancellation-fee e05-recurring-bookings e06-withdraw-response}"

APP_LABELS=("invitation_mvp:A" "booking_clean:B" "booking_debt:C" "marketplace_clean:D" "marketplace_debt:E")

echo "=== Debt Threshold Experiment Analyzer ==="
echo ""

for exp in $EXPERIMENTS; do
  ANALYSIS_FILE="$ROOT/experiments_debt/$exp/analysis.md"
  PROMPT_FILE="$ROOT/experiments_debt/$exp/prompt.md"
  RUNS_DIR="$ROOT/experiments_debt/$exp/runs"

  RUN_COUNT=$(find "$RUNS_DIR" -name "*.md" 2>/dev/null | wc -l)
  if [ "$RUN_COUNT" -eq 0 ]; then
    echo "SKIP $exp (no runs found)"
    continue
  fi

  if [ -f "$ANALYSIS_FILE" ]; then
    echo "SKIP $exp (analysis exists)"
    continue
  fi

  echo -n "ANALYZE $exp ($RUN_COUNT runs) ... "

  TMPFILE=$(mktemp)

  cat >> "$TMPFILE" << 'INSTRUCTIONS'
You are analyzing an experiment comparing AI responses to identical prompts given in up to 5 different codebases. The codebases represent different stages of a domain evolution and different levels of technical debt. You do not know which app has more or less debt.

INSTRUCTIONS

  echo "## Prompt Given" >> "$TMPFILE"
  echo "" >> "$TMPFILE"
  cat "$PROMPT_FILE" >> "$TMPFILE"
  echo "" >> "$TMPFILE"

  for label_pair in "${APP_LABELS[@]}"; do
    APP_NAME="${label_pair%%:*}"
    LABEL="${label_pair##*:}"

    FILES=$(find "$RUNS_DIR" -name "${APP_NAME}-*.md" 2>/dev/null | sort)
    [ -z "$FILES" ] && continue

    echo "## App $LABEL Responses" >> "$TMPFILE"
    echo "" >> "$TMPFILE"
    for f in $FILES; do
      echo "### $(basename "$f" .md)" >> "$TMPFILE"
      echo "" >> "$TMPFILE"
      cat "$f" >> "$TMPFILE"
      echo "" >> "$TMPFILE"
      echo "---" >> "$TMPFILE"
      echo "" >> "$TMPFILE"
    done
  done

  cat >> "$TMPFILE" << 'ANALYSIS_INSTRUCTIONS'

Analyze across these dimensions:

1. **Language/framing**: How does each app's AI describe the domain?
2. **Architectural choices**: What models, states, or abstractions were proposed?
3. **Model placement**: For code experiments, did the AI put new features on the correct model?
4. **State reuse vs invention**: Did the AI reuse existing states or create new ones?
5. **Correctness**: Any logical errors, bugs, or state transition mistakes?
6. **Scope**: Did responses stay on-task or add unrequested features?

Provide:
- Pattern summary per dimension
- Pairwise comparisons between all apps present
- Confidence levels
- Notable outliers
- Bottom line: one paragraph on the most important finding
ANALYSIS_INSTRUCTIONS

  RESULT=$(cat "$TMPFILE" | claude -p --dangerously-skip-permissions --disable-slash-commands --model opus 2>/dev/null) || true
  rm -f "$TMPFILE"

  if [ -n "$RESULT" ]; then
    {
      echo "# Analysis: $exp"
      echo ""
      echo "> Blind comparison — app identities not revealed to analyzer."
      echo ""
      echo "$RESULT"
    } > "$ANALYSIS_FILE"
    echo "done"
  else
    echo "FAILED"
  fi
done

echo ""
echo "=== Analysis complete ==="
```

```bash
chmod +x experiments_debt/analyze.sh
```

- [ ] **Step 4: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add experiments_debt/
git commit -m "feat: add debt threshold experiment infrastructure (6 experiments, 5 apps)"
```

---

### Task 7: Update CLAUDE.md and verify all apps

- [ ] **Step 1: Update root CLAUDE.md with new apps**

Add the 5 new apps to the structure section and key rules.

- [ ] **Step 2: Run all 5 app test suites**

```bash
cd /home/cutalion/code/affordance_test/invitation_mvp && bundle exec rspec
cd /home/cutalion/code/affordance_test/booking_clean && bundle exec rspec
cd /home/cutalion/code/affordance_test/booking_debt && bundle exec rspec
cd /home/cutalion/code/affordance_test/marketplace_clean && bundle exec rspec
cd /home/cutalion/code/affordance_test/marketplace_debt && bundle exec rspec
```

Expected: all specs pass in all 5 apps.

- [ ] **Step 3: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for debt threshold experiment apps"
```
