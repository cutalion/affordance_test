# Affordance Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build two identical Rails 8.1 JSON API apps — one using "Order" naming, one using "Request" naming with legacy invitation-era states — to study how naming affects AI reasoning.

**Architecture:** Rails 8.1 API-mode apps with a non-API admin section. AASM for state machines, service objects for business logic, log-based notification emulation. SQLite database, RSpec + FactoryBot for comprehensive testing.

**Tech Stack:** Ruby 3.3.5, Rails 8.1.3, AASM, RSpec, FactoryBot, SQLite

**Spec:** `docs/superpowers/specs/2026-04-06-affordance-test-design.md`

---

## File Structure: Order App

```
affordance_order/
├── Gemfile
├── config/
│   ├── routes.rb
│   ├── environments/test.rb (mailer config)
│   └── initializers/
│       └── admin_auth.rb
├── app/
│   ├── models/
│   │   ├── application_record.rb
│   │   ├── client.rb
│   │   ├── provider.rb
│   │   ├── order.rb
│   │   ├── card.rb
│   │   ├── payment.rb
│   │   └── review.rb
│   ├── controllers/
│   │   ├── application_controller.rb
│   │   ├── api/
│   │   │   ├── base_controller.rb
│   │   │   ├── clients_controller.rb
│   │   │   ├── providers_controller.rb
│   │   │   ├── orders_controller.rb
│   │   │   ├── cards_controller.rb
│   │   │   ├── payments_controller.rb
│   │   │   └── reviews_controller.rb
│   │   └── admin/
│   │       ├── base_controller.rb
│   │       ├── dashboard_controller.rb
│   │       ├── orders_controller.rb
│   │       ├── clients_controller.rb
│   │       ├── providers_controller.rb
│   │       └── payments_controller.rb
│   ├── services/
│   │   ├── orders/
│   │   │   ├── create_service.rb
│   │   │   ├── confirm_service.rb
│   │   │   ├── start_service.rb
│   │   │   ├── complete_service.rb
│   │   │   ├── cancel_service.rb
│   │   │   └── reject_service.rb
│   │   ├── notification_service.rb
│   │   └── payment_gateway.rb
│   ├── mailers/
│   │   ├── application_mailer.rb
│   │   └── order_mailer.rb
│   ├── jobs/
│   │   ├── payment_hold_job.rb
│   │   └── review_reminder_job.rb
│   └── views/
│       ├── layouts/
│       │   └── admin.html.erb
│       └── admin/
│           ├── dashboard/index.html.erb
│           ├── orders/index.html.erb
│           ├── orders/show.html.erb
│           ├── clients/index.html.erb
│           ├── clients/show.html.erb
│           ├── providers/index.html.erb
│           ├── providers/show.html.erb
│           ├── payments/index.html.erb
│           └── payments/show.html.erb
├── db/migrate/
│   ├── XXXXXX_create_clients.rb
│   ├── XXXXXX_create_providers.rb
│   ├── XXXXXX_create_orders.rb
│   ├── XXXXXX_create_cards.rb
│   ├── XXXXXX_create_payments.rb
│   └── XXXXXX_create_reviews.rb
└── spec/
    ├── rails_helper.rb
    ├── spec_helper.rb
    ├── factories/
    │   ├── clients.rb
    │   ├── providers.rb
    │   ├── orders.rb
    │   ├── cards.rb
    │   ├── payments.rb
    │   └── reviews.rb
    ├── models/
    │   ├── client_spec.rb
    │   ├── provider_spec.rb
    │   ├── order_spec.rb
    │   ├── card_spec.rb
    │   ├── payment_spec.rb
    │   └── review_spec.rb
    ├── services/
    │   ├── orders/
    │   │   ├── create_service_spec.rb
    │   │   ├── confirm_service_spec.rb
    │   │   ├── start_service_spec.rb
    │   │   ├── complete_service_spec.rb
    │   │   ├── cancel_service_spec.rb
    │   │   └── reject_service_spec.rb
    │   ├── notification_service_spec.rb
    │   └── payment_gateway_spec.rb
    ├── requests/
    │   ├── api/
    │   │   ├── clients_spec.rb
    │   │   ├── providers_spec.rb
    │   │   ├── orders_spec.rb
    │   │   ├── cards_spec.rb
    │   │   ├── payments_spec.rb
    │   │   └── reviews_spec.rb
    │   └── admin/
    │       ├── dashboard_spec.rb
    │       ├── orders_spec.rb
    │       ├── clients_spec.rb
    │       ├── providers_spec.rb
    │       └── payments_spec.rb
    ├── mailers/
    │   └── order_mailer_spec.rb
    ├── jobs/
    │   ├── payment_hold_job_spec.rb
    │   └── review_reminder_job_spec.rb
    └── support/
        ├── auth_helpers.rb
        └── notification_helpers.rb
```

## File Structure: Request App

Same as Order app with these naming changes:
- `order.rb` → `request.rb`, table `orders` → `requests`
- `services/orders/` → `services/requests/` + extra: `create_accepted_service.rb`, `decline_service.rb`; `confirm_service.rb` → `accept_service.rb`; `complete_service.rb` → `fulfill_service.rb`
- `order_mailer.rb` → `request_mailer.rb`
- `controllers/api/orders_controller.rb` → `controllers/api/requests_controller.rb`
- `controllers/admin/orders_controller.rb` → `controllers/admin/requests_controller.rb`
- All `views/admin/orders/` → `views/admin/requests/`
- All spec files follow same renaming pattern
- Route paths: `/api/orders` → `/api/requests`, `/admin/orders` → `/admin/requests`

---

### Task 1: Scaffold Order App

**Files:**
- Create: `affordance_order/` (entire Rails skeleton)
- Modify: `affordance_order/Gemfile`
- Create: `affordance_order/spec/rails_helper.rb`
- Create: `affordance_order/spec/spec_helper.rb`

- [ ] **Step 1: Generate Rails app**

```bash
cd /home/cutalion/code/affordance_test
rails new affordance_order --api --database=sqlite3 --skip-action-cable --skip-action-mailbox --skip-active-storage --skip-hotwire --skip-jbuilder --skip-test
```

- [ ] **Step 2: Add gems to Gemfile**

Add to the `Gemfile` (keep existing content, add these):

```ruby
gem "aasm"

group :development, :test do
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "shoulda-matchers"
  gem "database_cleaner-active_record"
end
```

- [ ] **Step 3: Bundle and install RSpec**

```bash
cd affordance_order
bundle install
bin/rails generate rspec:install
```

- [ ] **Step 4: Configure RSpec**

Replace `spec/rails_helper.rb` with:

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

- [ ] **Step 5: Create support files**

Create `spec/support/auth_helpers.rb`:

```ruby
module AuthHelpers
  def auth_headers(user)
    { "Authorization" => "Bearer #{user.api_token}" }
  end

  def admin_auth_headers
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "admin_password")
    { "Authorization" => credentials }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
```

Create `spec/support/notification_helpers.rb`:

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

- [ ] **Step 6: Configure admin auth initializer**

Create `config/initializers/admin_auth.rb`:

```ruby
Rails.application.config.admin_username = ENV.fetch("ADMIN_USERNAME", "admin")
Rails.application.config.admin_password = ENV.fetch("ADMIN_PASSWORD", "admin_password")
```

- [ ] **Step 7: Enable mailer in test environment**

Add to `config/environments/test.rb` (inside the configure block):

```ruby
config.action_mailer.delivery_method = :test
config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
```

- [ ] **Step 8: Verify setup**

```bash
cd affordance_order
bundle exec rspec
```

Expected: 0 examples, 0 failures

- [ ] **Step 9: Commit**

```bash
cd /home/cutalion/code/affordance_test
git init
git add affordance_order CLAUDE.md docs
git commit -m "feat: scaffold Order app with Rails 8.1, RSpec, AASM"
```

---

### Task 2: Order App — Models and Migrations

**Files:**
- Create: `affordance_order/db/migrate/*_create_clients.rb`
- Create: `affordance_order/db/migrate/*_create_providers.rb`
- Create: `affordance_order/db/migrate/*_create_orders.rb`
- Create: `affordance_order/db/migrate/*_create_cards.rb`
- Create: `affordance_order/db/migrate/*_create_payments.rb`
- Create: `affordance_order/db/migrate/*_create_reviews.rb`
- Create: `affordance_order/app/models/client.rb`
- Create: `affordance_order/app/models/provider.rb`
- Create: `affordance_order/app/models/order.rb`
- Create: `affordance_order/app/models/card.rb`
- Create: `affordance_order/app/models/payment.rb`
- Create: `affordance_order/app/models/review.rb`

- [ ] **Step 1: Generate migrations**

```bash
cd /home/cutalion/code/affordance_test/affordance_order

bin/rails generate migration CreateClients email:string name:string phone:string api_token:string notification_preferences:jsonb

bin/rails generate migration CreateProviders email:string name:string phone:string api_token:string rating:decimal specialization:string active:boolean notification_preferences:jsonb

bin/rails generate migration CreateOrders client:references provider:references scheduled_at:datetime duration_minutes:integer location:string notes:text state:string amount_cents:integer currency:string cancel_reason:text reject_reason:text started_at:datetime completed_at:datetime

bin/rails generate migration CreateCards client:references token:string last_four:string brand:string exp_month:integer exp_year:integer default:boolean

bin/rails generate migration CreatePayments order:references card:references amount_cents:integer currency:string fee_cents:integer status:string held_at:datetime charged_at:datetime refunded_at:datetime

bin/rails generate migration CreateReviews order:references author_type:string author_id:integer rating:integer body:text
```

- [ ] **Step 2: Edit migrations for proper defaults and indexes**

Edit `*_create_clients.rb`:

```ruby
class CreateClients < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :phone
      t.string :api_token, null: false
      t.jsonb :notification_preferences, default: { "push" => true, "sms" => true, "email" => true }, null: false

      t.timestamps
    end

    add_index :clients, :email, unique: true
    add_index :clients, :api_token, unique: true
  end
end
```

Edit `*_create_providers.rb`:

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
      t.boolean :active, default: true, null: false
      t.jsonb :notification_preferences, default: { "push" => true, "sms" => true, "email" => true }, null: false

      t.timestamps
    end

    add_index :providers, :email, unique: true
    add_index :providers, :api_token, unique: true
  end
end
```

Edit `*_create_orders.rb`:

```ruby
class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
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

Edit `*_create_cards.rb`:

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
      t.boolean :default, default: false, null: false

      t.timestamps
    end
  end
end
```

Edit `*_create_payments.rb`:

```ruby
class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :order, null: false, foreign_key: true
      t.references :card, foreign_key: true
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

Edit `*_create_reviews.rb`:

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

- [ ] **Step 3: Run migrations**

```bash
bin/rails db:migrate
```

- [ ] **Step 4: Write model code**

Create `app/models/client.rb`:

```ruby
class Client < ApplicationRecord
  has_many :orders, dependent: :destroy
  has_many :cards, dependent: :destroy
  has_many :reviews, as: :author, dependent: :destroy

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

Create `app/models/provider.rb`:

```ruby
class Provider < ApplicationRecord
  has_many :orders, dependent: :destroy
  has_many :reviews, as: :author, dependent: :destroy

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

Create `app/models/order.rb`:

```ruby
class Order < ApplicationRecord
  include AASM

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

Create `app/models/card.rb`:

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

Create `app/models/payment.rb`:

```ruby
class Payment < ApplicationRecord
  belongs_to :order
  belongs_to :card, optional: true

  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending held charged refunded] }

  scope :by_status, ->(status) { where(status: status) if status.present? }
  scope :pending_holds, -> {
    where(status: "pending")
      .joins(:order)
      .where("orders.scheduled_at BETWEEN ? AND ?", Time.current, 1.day.from_now)
  }

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

Create `app/models/review.rb`:

```ruby
class Review < ApplicationRecord
  belongs_to :order
  belongs_to :author, polymorphic: true

  validates :rating, presence: true, numericality: { in: 1..5 }
  validates :author_type, inclusion: { in: %w[Client Provider] }
  validates :order_id, uniqueness: { scope: [:author_type, :author_id], message: "already reviewed by this author" }
  validate :order_must_be_completed

  private

  def order_must_be_completed
    return if order.nil?
    unless order.completed?
      errors.add(:order, "must be completed before reviewing")
    end
  end
end
```

- [ ] **Step 5: Run migrations and verify**

```bash
bin/rails db:migrate
bin/rails runner "puts 'Models loaded OK'"
```

- [ ] **Step 6: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add affordance_order
git commit -m "feat(order): add models and migrations - Client, Provider, Order, Card, Payment, Review"
```

---

### Task 3: Order App — Factories and Model Specs

**Files:**
- Create: `affordance_order/spec/factories/clients.rb`
- Create: `affordance_order/spec/factories/providers.rb`
- Create: `affordance_order/spec/factories/orders.rb`
- Create: `affordance_order/spec/factories/cards.rb`
- Create: `affordance_order/spec/factories/payments.rb`
- Create: `affordance_order/spec/factories/reviews.rb`
- Create: `affordance_order/spec/models/client_spec.rb`
- Create: `affordance_order/spec/models/provider_spec.rb`
- Create: `affordance_order/spec/models/order_spec.rb`
- Create: `affordance_order/spec/models/card_spec.rb`
- Create: `affordance_order/spec/models/payment_spec.rb`
- Create: `affordance_order/spec/models/review_spec.rb`

- [ ] **Step 1: Create factories**

Create `spec/factories/clients.rb`:

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

Create `spec/factories/providers.rb`:

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

Create `spec/factories/orders.rb`:

```ruby
FactoryBot.define do
  factory :order do
    client
    provider
    scheduled_at { 3.days.from_now }
    duration_minutes { 120 }
    location { "123 Main St" }
    notes { "Please bring supplies" }
    amount_cents { 350_000 }
    currency { "RUB" }

    trait :confirmed do
      state { "confirmed" }
    end

    trait :in_progress do
      state { "in_progress" }
      started_at { Time.current }
    end

    trait :completed do
      state { "completed" }
      started_at { 2.hours.ago }
      completed_at { Time.current }
    end

    trait :canceled do
      state { "canceled" }
      cancel_reason { "Schedule changed" }
    end

    trait :rejected do
      state { "rejected" }
      reject_reason { "Cannot make it" }
    end

    trait :with_payment do
      after(:create) do |order|
        create(:payment, order: order, amount_cents: order.amount_cents, currency: order.currency)
      end
    end

    trait :with_card do
      after(:create) do |order|
        create(:card, client: order.client, default: true)
      end
    end

    trait :scheduled_tomorrow do
      scheduled_at { 1.day.from_now }
    end
  end
end
```

Create `spec/factories/cards.rb`:

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

    trait :expired do
      exp_year { 2023 }
    end
  end
end
```

Create `spec/factories/payments.rb`:

```ruby
FactoryBot.define do
  factory :payment do
    order
    amount_cents { 350_000 }
    currency { "RUB" }
    fee_cents { 35_000 }
    status { "pending" }

    trait :held do
      status { "held" }
      held_at { Time.current }
      card
    end

    trait :charged do
      status { "charged" }
      held_at { 1.hour.ago }
      charged_at { Time.current }
      card
    end

    trait :refunded do
      status { "refunded" }
      held_at { 2.hours.ago }
      charged_at { 1.hour.ago }
      refunded_at { Time.current }
      card
    end
  end
end
```

Create `spec/factories/reviews.rb`:

```ruby
FactoryBot.define do
  factory :review do
    association :order, :completed
    rating { 5 }
    body { "Excellent service!" }

    trait :by_client do
      association :author, factory: :client
    end

    trait :by_provider do
      association :author, factory: :provider
    end

    after(:build) do |review|
      if review.author.nil?
        review.author = review.order.client
      end
    end
  end
end
```

- [ ] **Step 2: Write model specs**

Create `spec/models/client_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Client, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:orders).dependent(:destroy) }
    it { is_expected.to have_many(:cards).dependent(:destroy) }
    it { is_expected.to have_many(:reviews).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:client) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:api_token) }
  end

  describe "api_token generation" do
    it "generates api_token on create" do
      client = create(:client)
      expect(client.api_token).to be_present
      expect(client.api_token.length).to eq(64)
    end

    it "does not overwrite existing token" do
      client = build(:client, api_token: "custom_token")
      client.save!
      expect(client.api_token).to eq("custom_token")
    end
  end

  describe "#default_card" do
    let(:client) { create(:client) }

    it "returns the default card" do
      card = create(:card, client: client, default: true)
      create(:card, client: client, default: false)
      expect(client.default_card).to eq(card)
    end

    it "returns nil when no default card" do
      create(:card, client: client, default: false)
      expect(client.default_card).to be_nil
    end
  end

  describe "notification_preferences" do
    it "has default preferences" do
      client = create(:client)
      expect(client.notification_preferences).to eq({
        "push" => true, "sms" => true, "email" => true
      })
    end
  end
end
```

Create `spec/models/provider_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Provider, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:orders).dependent(:destroy) }
    it { is_expected.to have_many(:reviews).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:provider) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:api_token) }
    it { is_expected.to validate_numericality_of(:rating).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(5) }
  end

  describe "api_token generation" do
    it "generates api_token on create" do
      provider = create(:provider)
      expect(provider.api_token).to be_present
    end
  end

  describe "scopes" do
    it ".active returns only active providers" do
      active = create(:provider, active: true)
      create(:provider, active: false)
      expect(Provider.active).to eq([active])
    end
  end
end
```

Create `spec/models/order_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Order, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:client) }
    it { is_expected.to belong_to(:provider) }
    it { is_expected.to have_one(:payment).dependent(:destroy) }
    it { is_expected.to have_many(:reviews).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:scheduled_at) }
    it { is_expected.to validate_presence_of(:duration_minutes) }
    it { is_expected.to validate_numericality_of(:duration_minutes).is_greater_than(0) }
    it { is_expected.to validate_presence_of(:amount_cents) }
    it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_presence_of(:currency) }

    context "when canceled" do
      subject { build(:order, :canceled) }
      it { is_expected.to validate_presence_of(:cancel_reason) }
    end

    context "when rejected" do
      subject { build(:order, :rejected) }
      it { is_expected.to validate_presence_of(:reject_reason) }
    end
  end

  describe "state machine" do
    let(:order) { create(:order) }

    describe "initial state" do
      it "starts as pending" do
        expect(order).to be_pending
      end
    end

    describe "#confirm" do
      it "transitions from pending to confirmed" do
        expect { order.confirm! }.to change(order, :state).from("pending").to("confirmed")
      end

      it "cannot transition from in_progress" do
        order = create(:order, :in_progress)
        expect { order.confirm! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#start" do
      it "transitions from confirmed to in_progress" do
        order = create(:order, :confirmed)
        expect { order.start! }.to change(order, :state).from("confirmed").to("in_progress")
      end

      it "sets started_at" do
        order = create(:order, :confirmed)
        freeze_time do
          order.start!
          expect(order.started_at).to eq(Time.current)
        end
      end

      it "cannot transition from pending" do
        expect { order.start! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#complete" do
      it "transitions from in_progress to completed" do
        order = create(:order, :in_progress)
        expect { order.complete! }.to change(order, :state).from("in_progress").to("completed")
      end

      it "sets completed_at" do
        order = create(:order, :in_progress)
        freeze_time do
          order.complete!
          expect(order.completed_at).to eq(Time.current)
        end
      end

      it "cannot transition from pending" do
        expect { order.complete! }.to raise_error(AASM::InvalidTransition)
      end

      it "cannot transition from confirmed" do
        order = create(:order, :confirmed)
        expect { order.complete! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#cancel" do
      it "transitions from pending to canceled" do
        order.cancel_reason = "Changed plans"
        expect { order.cancel! }.to change(order, :state).from("pending").to("canceled")
      end

      it "transitions from confirmed to canceled" do
        order = create(:order, :confirmed)
        order.cancel_reason = "Changed plans"
        expect { order.cancel! }.to change(order, :state).from("confirmed").to("canceled")
      end

      it "cannot transition from in_progress" do
        order = create(:order, :in_progress)
        order.cancel_reason = "Changed plans"
        expect { order.cancel! }.to raise_error(AASM::InvalidTransition)
      end

      it "cannot transition from completed" do
        order = create(:order, :completed)
        order.cancel_reason = "Changed plans"
        expect { order.cancel! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#reject" do
      it "transitions from confirmed to rejected" do
        order = create(:order, :confirmed)
        order.reject_reason = "Not available"
        expect { order.reject! }.to change(order, :state).from("confirmed").to("rejected")
      end

      it "transitions from in_progress to rejected" do
        order = create(:order, :in_progress)
        order.reject_reason = "Emergency"
        expect { order.reject! }.to change(order, :state).from("in_progress").to("rejected")
      end

      it "cannot transition from pending" do
        order.reject_reason = "Not available"
        expect { order.reject! }.to raise_error(AASM::InvalidTransition)
      end
    end
  end

  describe "scopes" do
    let!(:upcoming_order) { create(:order, scheduled_at: 2.days.from_now) }
    let!(:past_order) { create(:order, scheduled_at: 2.days.ago) }

    it ".upcoming returns future orders" do
      expect(Order.upcoming).to include(upcoming_order)
      expect(Order.upcoming).not_to include(past_order)
    end

    it ".past returns past orders" do
      expect(Order.past).to include(past_order)
      expect(Order.past).not_to include(upcoming_order)
    end

    it ".by_state filters by state" do
      confirmed = create(:order, :confirmed)
      expect(Order.by_state("confirmed")).to include(confirmed)
      expect(Order.by_state("confirmed")).not_to include(upcoming_order)
    end

    it ".by_state returns all when state is blank" do
      expect(Order.by_state(nil)).to include(upcoming_order, past_order)
    end

    it ".sorted orders by scheduled_at desc" do
      expect(Order.sorted.first).to eq(upcoming_order)
    end
  end
end
```

Create `spec/models/card_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Card, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:client) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:token) }
    it { is_expected.to validate_presence_of(:last_four) }
    it { is_expected.to validate_length_of(:last_four).is_equal_to(4) }
    it { is_expected.to validate_presence_of(:brand) }
    it { is_expected.to validate_inclusion_of(:brand).in_array(%w[visa mastercard amex mir]) }
    it { is_expected.to validate_presence_of(:exp_month) }
    it { is_expected.to validate_presence_of(:exp_year) }
  end

  describe "#make_default!" do
    let(:client) { create(:client) }
    let!(:card1) { create(:card, client: client, default: true) }
    let!(:card2) { create(:card, client: client, default: false) }

    it "sets the card as default" do
      card2.make_default!
      expect(card2.reload).to be_default
    end

    it "unsets other cards as default" do
      card2.make_default!
      expect(card1.reload).not_to be_default
    end
  end

  describe "ensure_single_default" do
    let(:client) { create(:client) }

    it "unsets other defaults when saving a new default card" do
      card1 = create(:card, client: client, default: true)
      create(:card, client: client, default: true)
      expect(card1.reload).not_to be_default
    end
  end
end
```

Create `spec/models/payment_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Payment, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:order) }
    it { is_expected.to belong_to(:card).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:amount_cents) }
    it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_presence_of(:currency) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[pending held charged refunded]) }
  end

  describe "#hold!" do
    it "sets status to held with timestamp" do
      payment = create(:payment)
      freeze_time do
        payment.hold!
        expect(payment.status).to eq("held")
        expect(payment.held_at).to eq(Time.current)
      end
    end
  end

  describe "#charge!" do
    it "sets status to charged with timestamp" do
      payment = create(:payment, :held)
      freeze_time do
        payment.charge!
        expect(payment.status).to eq("charged")
        expect(payment.charged_at).to eq(Time.current)
      end
    end
  end

  describe "#refund!" do
    it "sets status to refunded with timestamp" do
      payment = create(:payment, :charged)
      freeze_time do
        payment.refund!
        expect(payment.status).to eq("refunded")
        expect(payment.refunded_at).to eq(Time.current)
      end
    end
  end

  describe "scopes" do
    it ".by_status filters by status" do
      held = create(:payment, :held)
      create(:payment)
      expect(Payment.by_status("held")).to eq([held])
    end
  end
end
```

Create `spec/models/review_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Review, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:order) }
    it { is_expected.to belong_to(:author) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:rating) }
    it { is_expected.to validate_numericality_of(:rating).is_in(1..5) }
    it { is_expected.to validate_inclusion_of(:author_type).in_array(%w[Client Provider]) }

    it "requires order to be completed" do
      order = create(:order, :confirmed)
      review = build(:review, order: order, author: order.client)
      expect(review).not_to be_valid
      expect(review.errors[:order]).to include("must be completed before reviewing")
    end

    it "allows review on completed order" do
      order = create(:order, :completed)
      review = build(:review, order: order, author: order.client)
      expect(review).to be_valid
    end

    it "enforces one review per author per order" do
      order = create(:order, :completed)
      create(:review, order: order, author: order.client)
      duplicate = build(:review, order: order, author: order.client)
      expect(duplicate).not_to be_valid
    end

    it "allows different authors to review same order" do
      order = create(:order, :completed)
      create(:review, order: order, author: order.client)
      provider_review = build(:review, order: order, author: order.provider)
      expect(provider_review).to be_valid
    end
  end
end
```

- [ ] **Step 3: Run model specs**

```bash
cd /home/cutalion/code/affordance_test/affordance_order
bundle exec rspec spec/models
```

Expected: All pass (fix any issues)

- [ ] **Step 4: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add affordance_order/spec
git commit -m "feat(order): add factories and model specs"
```

---

### Task 4: Order App — Services (Notification, Payment Gateway, Order Services)

**Files:**
- Create: `affordance_order/app/services/notification_service.rb`
- Create: `affordance_order/app/services/payment_gateway.rb`
- Create: `affordance_order/app/services/orders/create_service.rb`
- Create: `affordance_order/app/services/orders/confirm_service.rb`
- Create: `affordance_order/app/services/orders/start_service.rb`
- Create: `affordance_order/app/services/orders/complete_service.rb`
- Create: `affordance_order/app/services/orders/cancel_service.rb`
- Create: `affordance_order/app/services/orders/reject_service.rb`

- [ ] **Step 1: Create NotificationService**

Create `app/services/notification_service.rb`:

```ruby
class NotificationService
  CHANNELS = %w[push sms email].freeze
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
    mailer_class = OrderMailer
    if mailer_class.respond_to?(@event)
      mailer_class.public_send(@event, @recipient, @payload).deliver_later
    end
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

- [ ] **Step 2: Create PaymentGateway**

Create `app/services/payment_gateway.rb`:

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
    card = @payment.order.client.default_card
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

- [ ] **Step 3: Create Order service objects**

Create `app/services/orders/create_service.rb`:

```ruby
module Orders
  class CreateService
    def initialize(client:, provider:, params:)
      @client = client
      @provider = provider
      @params = params
    end

    def call
      order = Order.new(
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

Create `app/services/orders/confirm_service.rb`:

```ruby
module Orders
  class ConfirmService
    def initialize(order:, provider:)
      @order = order
      @provider = provider
    end

    def call
      return error("Not your order") unless @order.provider_id == @provider.id

      @order.confirm!
      NotificationService.notify(@order.client, :order_confirmed, order_id: @order.id)
      { success: true, order: @order }
    rescue AASM::InvalidTransition
      error("Cannot confirm order in #{@order.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

Create `app/services/orders/start_service.rb`:

```ruby
module Orders
  class StartService
    def initialize(order:, provider:)
      @order = order
      @provider = provider
    end

    def call
      return error("Not your order") unless @order.provider_id == @provider.id

      @order.start!
      NotificationService.notify(@order.client, :order_started, order_id: @order.id)
      { success: true, order: @order }
    rescue AASM::InvalidTransition
      error("Cannot start order in #{@order.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

Create `app/services/orders/complete_service.rb`:

```ruby
module Orders
  class CompleteService
    def initialize(order:, provider:)
      @order = order
      @provider = provider
    end

    def call
      return error("Not your order") unless @order.provider_id == @provider.id

      @order.complete!

      if @order.payment&.status == "held"
        PaymentGateway.charge(@order.payment)
      end

      NotificationService.notify(@order.client, :order_completed, order_id: @order.id)
      NotificationService.notify(@order.provider, :order_completed, order_id: @order.id)
      { success: true, order: @order }
    rescue AASM::InvalidTransition
      error("Cannot complete order in #{@order.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

Create `app/services/orders/cancel_service.rb`:

```ruby
module Orders
  class CancelService
    def initialize(order:, client:, reason:)
      @order = order
      @client = client
      @reason = reason
    end

    def call
      return error("Not your order") unless @order.client_id == @client.id
      return error("Cancel reason is required") if @reason.blank?

      @order.cancel_reason = @reason
      @order.cancel!

      if @order.payment && %w[held charged].include?(@order.payment.status)
        PaymentGateway.refund(@order.payment)
      end

      NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
      { success: true, order: @order }
    rescue AASM::InvalidTransition
      error("Cannot cancel order in #{@order.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

Create `app/services/orders/reject_service.rb`:

```ruby
module Orders
  class RejectService
    def initialize(order:, provider:, reason:)
      @order = order
      @provider = provider
      @reason = reason
    end

    def call
      return error("Not your order") unless @order.provider_id == @provider.id
      return error("Reject reason is required") if @reason.blank?

      @order.reject_reason = @reason
      @order.reject!

      if @order.payment && %w[held charged].include?(@order.payment.status)
        PaymentGateway.refund(@order.payment)
      end

      NotificationService.notify(@order.client, :order_rejected, order_id: @order.id)
      { success: true, order: @order }
    rescue AASM::InvalidTransition
      error("Cannot reject order in #{@order.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

- [ ] **Step 4: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add affordance_order/app/services
git commit -m "feat(order): add services - NotificationService, PaymentGateway, Order lifecycle services"
```

---

### Task 5: Order App — Service Specs

**Files:**
- Create: `affordance_order/spec/services/notification_service_spec.rb`
- Create: `affordance_order/spec/services/payment_gateway_spec.rb`
- Create: `affordance_order/spec/services/orders/create_service_spec.rb`
- Create: `affordance_order/spec/services/orders/confirm_service_spec.rb`
- Create: `affordance_order/spec/services/orders/start_service_spec.rb`
- Create: `affordance_order/spec/services/orders/complete_service_spec.rb`
- Create: `affordance_order/spec/services/orders/cancel_service_spec.rb`
- Create: `affordance_order/spec/services/orders/reject_service_spec.rb`

- [ ] **Step 1: Write NotificationService spec**

Create `spec/services/notification_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe NotificationService do
  let(:client) { create(:client, phone: "+79001234567") }

  describe ".notify" do
    it "writes push notification to log" do
      NotificationService.notify(client, :order_confirmed, order_id: 1)
      log = read_notification_log
      expect(log).to include("[PUSH] to=client_#{client.id} event=order_confirmed order_id=1")
    end

    it "writes SMS notification to log" do
      NotificationService.notify(client, :order_confirmed, order_id: 1)
      log = read_notification_log
      expect(log).to include("[SMS] to=+79001234567 event=order_confirmed")
    end

    it "writes email notification to log" do
      NotificationService.notify(client, :order_confirmed, order_id: 1)
      log = read_notification_log
      expect(log).to include("[EMAIL] to=#{client.email} event=order_confirmed")
    end

    it "respects push preference" do
      client.update!(notification_preferences: { "push" => false, "sms" => true, "email" => true })
      NotificationService.notify(client, :order_confirmed, order_id: 1)
      log = read_notification_log
      expect(log).not_to include("[PUSH]")
      expect(log).to include("[SMS]")
    end

    it "respects sms preference" do
      client.update!(notification_preferences: { "push" => true, "sms" => false, "email" => true })
      NotificationService.notify(client, :order_confirmed, order_id: 1)
      log = read_notification_log
      expect(log).not_to include("[SMS]")
    end

    it "respects email preference" do
      client.update!(notification_preferences: { "push" => true, "sms" => true, "email" => false })
      NotificationService.notify(client, :order_confirmed, order_id: 1)
      log = read_notification_log
      expect(log).not_to include("[EMAIL]")
    end
  end
end
```

- [ ] **Step 2: Write PaymentGateway spec**

Create `spec/services/payment_gateway_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe PaymentGateway do
  let(:client) { create(:client) }
  let!(:card) { create(:card, client: client, default: true) }
  let(:order) { create(:order, client: client) }
  let(:payment) { create(:payment, order: order) }

  describe ".hold" do
    it "holds payment with default card" do
      result = PaymentGateway.hold(payment)
      expect(result[:success]).to be true
      expect(payment.reload.status).to eq("held")
      expect(payment.card).to eq(card)
      expect(payment.held_at).to be_present
    end

    it "logs the hold action" do
      PaymentGateway.hold(payment)
      log = read_payment_log
      expect(log).to include("[PAYMENT] action=hold payment_id=#{payment.id}")
      expect(log).to include("card=*#{card.last_four}")
    end

    it "fails without default card" do
      card.update!(default: false)
      result = PaymentGateway.hold(payment)
      expect(result[:success]).to be false
      expect(result[:error]).to eq("No default card")
    end
  end

  describe ".charge" do
    let(:payment) { create(:payment, :held, order: order, card: card) }

    it "charges held payment" do
      result = PaymentGateway.charge(payment)
      expect(result[:success]).to be true
      expect(payment.reload.status).to eq("charged")
      expect(payment.charged_at).to be_present
    end

    it "logs the charge action" do
      PaymentGateway.charge(payment)
      log = read_payment_log
      expect(log).to include("[PAYMENT] action=charge payment_id=#{payment.id}")
    end

    it "fails if payment is not held" do
      pending_payment = create(:payment, order: order)
      result = PaymentGateway.charge(pending_payment)
      expect(result[:success]).to be false
    end
  end

  describe ".refund" do
    let(:payment) { create(:payment, :charged, order: order, card: card) }

    it "refunds charged payment" do
      result = PaymentGateway.refund(payment)
      expect(result[:success]).to be true
      expect(payment.reload.status).to eq("refunded")
      expect(payment.refunded_at).to be_present
    end

    it "refunds held payment" do
      held_payment = create(:payment, :held, order: order, card: card)
      result = PaymentGateway.refund(held_payment)
      expect(result[:success]).to be true
    end

    it "logs the refund action" do
      PaymentGateway.refund(payment)
      log = read_payment_log
      expect(log).to include("[PAYMENT] action=refund payment_id=#{payment.id}")
    end

    it "fails if payment is pending" do
      pending_payment = create(:payment, order: order)
      result = PaymentGateway.refund(pending_payment)
      expect(result[:success]).to be false
    end
  end
end
```

- [ ] **Step 3: Write Order service specs**

Create `spec/services/orders/create_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Orders::CreateService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:params) do
    {
      scheduled_at: 3.days.from_now,
      duration_minutes: 120,
      location: "123 Main St",
      notes: "Bring supplies",
      amount_cents: 350_000,
      currency: "RUB"
    }
  end

  describe "#call" do
    it "creates an order in pending state" do
      result = described_class.new(client: client, provider: provider, params: params).call
      expect(result[:success]).to be true
      expect(result[:order]).to be_persisted
      expect(result[:order].state).to eq("pending")
    end

    it "creates a pending payment" do
      result = described_class.new(client: client, provider: provider, params: params).call
      payment = result[:order].payment
      expect(payment).to be_present
      expect(payment.status).to eq("pending")
      expect(payment.amount_cents).to eq(350_000)
      expect(payment.fee_cents).to eq(35_000)
    end

    it "notifies provider" do
      described_class.new(client: client, provider: provider, params: params).call
      log = read_notification_log
      expect(log).to include("event=order_created")
    end

    it "returns errors on invalid params" do
      params[:amount_cents] = nil
      result = described_class.new(client: client, provider: provider, params: params).call
      expect(result[:success]).to be false
      expect(result[:errors]).to be_present
    end
  end
end
```

Create `spec/services/orders/confirm_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Orders::ConfirmService do
  let(:order) { create(:order) }
  let(:provider) { order.provider }

  describe "#call" do
    it "confirms a pending order" do
      result = described_class.new(order: order, provider: provider).call
      expect(result[:success]).to be true
      expect(order.reload.state).to eq("confirmed")
    end

    it "notifies client" do
      described_class.new(order: order, provider: provider).call
      log = read_notification_log
      expect(log).to include("event=order_confirmed")
    end

    it "fails if not the order's provider" do
      other_provider = create(:provider)
      result = described_class.new(order: order, provider: other_provider).call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Not your order")
    end

    it "fails if order is not pending" do
      order = create(:order, :completed)
      result = described_class.new(order: order, provider: order.provider).call
      expect(result[:success]).to be false
      expect(result[:error]).to include("Cannot confirm")
    end
  end
end
```

Create `spec/services/orders/start_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Orders::StartService do
  let(:order) { create(:order, :confirmed) }
  let(:provider) { order.provider }

  describe "#call" do
    it "starts a confirmed order" do
      result = described_class.new(order: order, provider: provider).call
      expect(result[:success]).to be true
      expect(order.reload.state).to eq("in_progress")
    end

    it "notifies client" do
      described_class.new(order: order, provider: provider).call
      log = read_notification_log
      expect(log).to include("event=order_started")
    end

    it "fails if not the order's provider" do
      other_provider = create(:provider)
      result = described_class.new(order: order, provider: other_provider).call
      expect(result[:success]).to be false
    end

    it "fails if order is pending" do
      order = create(:order)
      result = described_class.new(order: order, provider: order.provider).call
      expect(result[:success]).to be false
    end
  end
end
```

Create `spec/services/orders/complete_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Orders::CompleteService do
  let(:client) { create(:client) }
  let!(:card) { create(:card, client: client, default: true) }
  let(:order) { create(:order, :in_progress, client: client) }
  let(:provider) { order.provider }

  describe "#call" do
    it "completes an in_progress order" do
      result = described_class.new(order: order, provider: provider).call
      expect(result[:success]).to be true
      expect(order.reload.state).to eq("completed")
    end

    it "charges held payment" do
      payment = create(:payment, :held, order: order, card: card)
      described_class.new(order: order, provider: provider).call
      expect(payment.reload.status).to eq("charged")
    end

    it "notifies both client and provider" do
      described_class.new(order: order, provider: provider).call
      log = read_notification_log
      expect(log).to include("to=client_#{client.id} event=order_completed")
      expect(log).to include("to=provider_#{provider.id} event=order_completed")
    end

    it "fails if not the order's provider" do
      other_provider = create(:provider)
      result = described_class.new(order: order, provider: other_provider).call
      expect(result[:success]).to be false
    end
  end
end
```

Create `spec/services/orders/cancel_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Orders::CancelService do
  let(:order) { create(:order) }
  let(:client) { order.client }

  describe "#call" do
    it "cancels a pending order" do
      result = described_class.new(order: order, client: client, reason: "Changed plans").call
      expect(result[:success]).to be true
      expect(order.reload.state).to eq("canceled")
      expect(order.cancel_reason).to eq("Changed plans")
    end

    it "cancels a confirmed order" do
      order = create(:order, :confirmed)
      result = described_class.new(order: order, client: order.client, reason: "Changed plans").call
      expect(result[:success]).to be true
    end

    it "refunds held payment" do
      card = create(:card, client: client, default: true)
      payment = create(:payment, :held, order: order, card: card)
      described_class.new(order: order, client: client, reason: "Changed plans").call
      expect(payment.reload.status).to eq("refunded")
    end

    it "notifies provider" do
      described_class.new(order: order, client: client, reason: "Changed plans").call
      log = read_notification_log
      expect(log).to include("event=order_canceled")
    end

    it "fails without reason" do
      result = described_class.new(order: order, client: client, reason: "").call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Cancel reason is required")
    end

    it "fails if not the order's client" do
      other_client = create(:client)
      result = described_class.new(order: order, client: other_client, reason: "Changed plans").call
      expect(result[:success]).to be false
    end

    it "fails for in_progress order" do
      order = create(:order, :in_progress)
      result = described_class.new(order: order, client: order.client, reason: "Changed plans").call
      expect(result[:success]).to be false
    end
  end
end
```

Create `spec/services/orders/reject_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Orders::RejectService do
  let(:order) { create(:order, :confirmed) }
  let(:provider) { order.provider }

  describe "#call" do
    it "rejects a confirmed order" do
      result = described_class.new(order: order, provider: provider, reason: "Not available").call
      expect(result[:success]).to be true
      expect(order.reload.state).to eq("rejected")
      expect(order.reject_reason).to eq("Not available")
    end

    it "rejects an in_progress order" do
      order = create(:order, :in_progress)
      result = described_class.new(order: order, provider: order.provider, reason: "Emergency").call
      expect(result[:success]).to be true
    end

    it "refunds held payment" do
      card = create(:card, client: order.client, default: true)
      payment = create(:payment, :held, order: order, card: card)
      described_class.new(order: order, provider: provider, reason: "Not available").call
      expect(payment.reload.status).to eq("refunded")
    end

    it "notifies client" do
      described_class.new(order: order, provider: provider, reason: "Not available").call
      log = read_notification_log
      expect(log).to include("event=order_rejected")
    end

    it "fails without reason" do
      result = described_class.new(order: order, provider: provider, reason: "").call
      expect(result[:success]).to be false
    end

    it "fails for pending order" do
      order = create(:order)
      result = described_class.new(order: order, provider: order.provider, reason: "Not available").call
      expect(result[:success]).to be false
    end
  end
end
```

- [ ] **Step 4: Run service specs**

```bash
cd /home/cutalion/code/affordance_test/affordance_order
bundle exec rspec spec/services
```

- [ ] **Step 5: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add affordance_order/spec/services
git commit -m "feat(order): add service specs"
```

---

### Task 6: Order App — Mailer

**Files:**
- Create: `affordance_order/app/mailers/application_mailer.rb`
- Create: `affordance_order/app/mailers/order_mailer.rb`
- Create: `affordance_order/spec/mailers/order_mailer_spec.rb`

- [ ] **Step 1: Create mailers**

Create `app/mailers/application_mailer.rb`:

```ruby
class ApplicationMailer < ActionMailer::Base
  default from: "noreply@servicemarket.example.com"
  layout false
end
```

Create `app/mailers/order_mailer.rb`:

```ruby
class OrderMailer < ApplicationMailer
  def order_created(recipient, payload)
    @order_id = payload[:order_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "New order ##{@order_id}")
  end

  def order_confirmed(recipient, payload)
    @order_id = payload[:order_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "Order ##{@order_id} confirmed")
  end

  def order_started(recipient, payload)
    @order_id = payload[:order_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "Order ##{@order_id} started")
  end

  def order_completed(recipient, payload)
    @order_id = payload[:order_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "Order ##{@order_id} completed")
  end

  def order_canceled(recipient, payload)
    @order_id = payload[:order_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "Order ##{@order_id} canceled")
  end

  def order_rejected(recipient, payload)
    @order_id = payload[:order_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "Order ##{@order_id} rejected")
  end

  def review_reminder(recipient, payload)
    @order_id = payload[:order_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "Please review order ##{@order_id}")
  end
end
```

- [ ] **Step 2: Create mailer views (minimal text)**

Create `app/views/order_mailer/order_created.text.erb`:

```erb
Hello <%= @recipient.name %>,

A new order #<%= @order_id %> has been created for you.

Thanks,
Service Market
```

Create similar text templates for each mailer method (order_confirmed, order_started, order_completed, order_canceled, order_rejected, review_reminder) — all follow the same pattern with the appropriate verb.

- [ ] **Step 3: Write mailer spec**

Create `spec/mailers/order_mailer_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe OrderMailer, type: :mailer do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:payload) { { order_id: 42 } }

  describe "#order_created" do
    let(:mail) { described_class.order_created(provider, payload) }

    it "sends to provider" do
      expect(mail.to).to eq([provider.email])
    end

    it "sets correct subject" do
      expect(mail.subject).to eq("New order #42")
    end
  end

  describe "#order_confirmed" do
    let(:mail) { described_class.order_confirmed(client, payload) }

    it "sends to client" do
      expect(mail.to).to eq([client.email])
    end

    it "sets correct subject" do
      expect(mail.subject).to eq("Order #42 confirmed")
    end
  end

  describe "#order_started" do
    let(:mail) { described_class.order_started(client, payload) }

    it "sends to client" do
      expect(mail.to).to eq([client.email])
    end

    it "sets correct subject" do
      expect(mail.subject).to eq("Order #42 started")
    end
  end

  describe "#order_completed" do
    let(:mail) { described_class.order_completed(client, payload) }

    it "sends to client" do
      expect(mail.to).to eq([client.email])
    end

    it "sets correct subject" do
      expect(mail.subject).to eq("Order #42 completed")
    end
  end

  describe "#order_canceled" do
    let(:mail) { described_class.order_canceled(provider, payload) }

    it "sends to provider" do
      expect(mail.to).to eq([provider.email])
    end

    it "sets correct subject" do
      expect(mail.subject).to eq("Order #42 canceled")
    end
  end

  describe "#order_rejected" do
    let(:mail) { described_class.order_rejected(client, payload) }

    it "sends to client" do
      expect(mail.to).to eq([client.email])
    end

    it "sets correct subject" do
      expect(mail.subject).to eq("Order #42 rejected")
    end
  end

  describe "#review_reminder" do
    let(:mail) { described_class.review_reminder(client, payload) }

    it "sends to client" do
      expect(mail.to).to eq([client.email])
    end

    it "sets correct subject" do
      expect(mail.subject).to eq("Please review order #42")
    end
  end
end
```

- [ ] **Step 4: Run mailer specs**

```bash
bundle exec rspec spec/mailers
```

- [ ] **Step 5: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add affordance_order/app/mailers affordance_order/app/views/order_mailer affordance_order/spec/mailers
git commit -m "feat(order): add OrderMailer with specs"
```

---

### Task 7: Order App — API Controllers

**Files:**
- Create: `affordance_order/app/controllers/api/base_controller.rb`
- Create: `affordance_order/app/controllers/api/clients_controller.rb`
- Create: `affordance_order/app/controllers/api/providers_controller.rb`
- Create: `affordance_order/app/controllers/api/orders_controller.rb`
- Create: `affordance_order/app/controllers/api/cards_controller.rb`
- Create: `affordance_order/app/controllers/api/payments_controller.rb`
- Create: `affordance_order/app/controllers/api/reviews_controller.rb`
- Modify: `affordance_order/config/routes.rb`

- [ ] **Step 1: Create base controller with auth**

Create `app/controllers/api/base_controller.rb`:

```ruby
module Api
  class BaseController < ActionController::API
    before_action :authenticate!

    private

    def authenticate!
      token = request.headers["Authorization"]&.split("Bearer ")&.last
      @current_client = Client.find_by(api_token: token)
      @current_provider = Provider.find_by(api_token: token) unless @current_client
      render_unauthorized unless current_user
    end

    def current_user
      @current_client || @current_provider
    end

    def current_client!
      render_forbidden("Client access required") unless @current_client
      @current_client
    end

    def current_provider!
      render_forbidden("Provider access required") unless @current_provider
      @current_provider
    end

    def render_unauthorized
      render json: { error: "Unauthorized" }, status: :unauthorized
    end

    def render_forbidden(message = "Forbidden")
      render json: { error: message }, status: :forbidden
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

- [ ] **Step 2: Create user controllers**

Create `app/controllers/api/clients_controller.rb`:

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
      render json: client_json(current_client!)
    end

    private

    def client_params
      params.require(:client).permit(:email, :name, :phone)
    end

    def client_json(client)
      return unless client
      {
        id: client.id,
        email: client.email,
        name: client.name,
        phone: client.phone,
        api_token: client.api_token,
        notification_preferences: client.notification_preferences,
        created_at: client.created_at
      }
    end
  end
end
```

Create `app/controllers/api/providers_controller.rb`:

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
      render json: provider_json(current_provider!)
    end

    private

    def provider_params
      params.require(:provider).permit(:email, :name, :phone, :specialization)
    end

    def provider_json(provider)
      return unless provider
      {
        id: provider.id,
        email: provider.email,
        name: provider.name,
        phone: provider.phone,
        specialization: provider.specialization,
        rating: provider.rating,
        active: provider.active,
        api_token: provider.api_token,
        notification_preferences: provider.notification_preferences,
        created_at: provider.created_at
      }
    end
  end
end
```

- [ ] **Step 3: Create orders controller**

Create `app/controllers/api/orders_controller.rb`:

```ruby
module Api
  class OrdersController < BaseController
    before_action :find_order, only: [:show, :confirm, :start, :complete, :cancel, :reject]

    def index
      orders = if @current_client
        @current_client.orders
      else
        @current_provider.orders
      end

      orders = orders.by_state(params[:state])
                     .scheduled_between(params[:from], params[:to])
                     .sorted
                     .page(params[:page])

      render json: orders.map { |o| order_json(o) }
    end

    def show
      render json: order_json(@order, detailed: true)
    end

    def create
      client = current_client!
      return unless client

      result = Orders::CreateService.new(
        client: client,
        provider: Provider.find(params[:provider_id]),
        params: order_params
      ).call

      if result[:success]
        render json: order_json(result[:order]), status: :created
      else
        render_unprocessable(result[:errors]&.full_messages || [result[:error]])
      end
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Provider not found" }, status: :not_found
    end

    def confirm
      provider = current_provider!
      return unless provider

      result = Orders::ConfirmService.new(order: @order, provider: provider).call
      render_service_result(result)
    end

    def start
      provider = current_provider!
      return unless provider

      result = Orders::StartService.new(order: @order, provider: provider).call
      render_service_result(result)
    end

    def complete
      provider = current_provider!
      return unless provider

      result = Orders::CompleteService.new(order: @order, provider: provider).call
      render_service_result(result)
    end

    def cancel
      client = current_client!
      return unless client

      result = Orders::CancelService.new(
        order: @order, client: client, reason: params[:reason]
      ).call
      render_service_result(result)
    end

    def reject
      provider = current_provider!
      return unless provider

      result = Orders::RejectService.new(
        order: @order, provider: provider, reason: params[:reason]
      ).call
      render_service_result(result)
    end

    private

    def find_order
      @order = Order.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_not_found
    end

    def order_params
      params.require(:order).permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
    end

    def render_service_result(result)
      if result[:success]
        render json: order_json(result[:order])
      else
        render json: { error: result[:error] }, status: :unprocessable_entity
      end
    end

    def order_json(order, detailed: false)
      json = {
        id: order.id,
        client_id: order.client_id,
        provider_id: order.provider_id,
        state: order.state,
        scheduled_at: order.scheduled_at,
        duration_minutes: order.duration_minutes,
        location: order.location,
        amount_cents: order.amount_cents,
        currency: order.currency,
        created_at: order.created_at
      }

      if detailed
        json[:notes] = order.notes
        json[:cancel_reason] = order.cancel_reason
        json[:reject_reason] = order.reject_reason
        json[:started_at] = order.started_at
        json[:completed_at] = order.completed_at
        json[:payment] = order.payment&.then { |p|
          { id: p.id, status: p.status, amount_cents: p.amount_cents, fee_cents: p.fee_cents }
        }
      end

      json
    end
  end
end
```

- [ ] **Step 4: Create cards controller**

Create `app/controllers/api/cards_controller.rb`:

```ruby
module Api
  class CardsController < BaseController
    before_action :require_client!
    before_action :find_card, only: [:destroy, :set_default]

    def index
      render json: @current_client.cards.map { |c| card_json(c) }
    end

    def create
      card = @current_client.cards.new(card_params)
      card.default = true if @current_client.cards.empty?

      if card.save
        render json: card_json(card), status: :created
      else
        render_unprocessable(card.errors.full_messages)
      end
    end

    def destroy
      @card.destroy!
      head :no_content
    end

    def set_default
      @card.make_default!
      render json: card_json(@card)
    end

    private

    def require_client!
      current_client!
    end

    def find_card
      @card = @current_client.cards.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_not_found
    end

    def card_params
      params.require(:card).permit(:token, :last_four, :brand, :exp_month, :exp_year)
    end

    def card_json(card)
      {
        id: card.id,
        last_four: card.last_four,
        brand: card.brand,
        exp_month: card.exp_month,
        exp_year: card.exp_year,
        default: card.default,
        created_at: card.created_at
      }
    end
  end
end
```

- [ ] **Step 5: Create payments controller**

Create `app/controllers/api/payments_controller.rb`:

```ruby
module Api
  class PaymentsController < BaseController
    def index
      payments = if @current_client
        Payment.joins(:order).where(orders: { client_id: @current_client.id })
      else
        Payment.joins(:order).where(orders: { provider_id: @current_provider.id })
      end

      payments = payments.by_status(params[:status]).order(created_at: :desc)
      render json: payments.map { |p| payment_json(p) }
    end

    def show
      payment = Payment.find(params[:id])
      order = payment.order
      unless order.client_id == @current_client&.id || order.provider_id == @current_provider&.id
        return render_forbidden
      end
      render json: payment_json(payment)
    rescue ActiveRecord::RecordNotFound
      render_not_found
    end

    private

    def payment_json(payment)
      {
        id: payment.id,
        order_id: payment.order_id,
        amount_cents: payment.amount_cents,
        currency: payment.currency,
        fee_cents: payment.fee_cents,
        status: payment.status,
        held_at: payment.held_at,
        charged_at: payment.charged_at,
        refunded_at: payment.refunded_at,
        created_at: payment.created_at
      }
    end
  end
end
```

- [ ] **Step 6: Create reviews controller**

Create `app/controllers/api/reviews_controller.rb`:

```ruby
module Api
  class ReviewsController < BaseController
    before_action :find_order

    def index
      reviews = @order.reviews
      render json: reviews.map { |r| review_json(r) }
    end

    def create
      review = @order.reviews.new(
        author: current_user,
        rating: params[:rating],
        body: params[:body]
      )

      if review.save
        update_provider_rating if current_user.is_a?(Client)
        render json: review_json(review), status: :created
      else
        render_unprocessable(review.errors.full_messages)
      end
    end

    private

    def find_order
      @order = Order.find(params[:order_id])
    rescue ActiveRecord::RecordNotFound
      render_not_found
    end

    def review_json(review)
      {
        id: review.id,
        order_id: review.order_id,
        author_type: review.author_type,
        author_id: review.author_id,
        rating: review.rating,
        body: review.body,
        created_at: review.created_at
      }
    end

    def update_provider_rating
      provider = @order.provider
      avg = provider.reviews.average(:rating)
      provider.update!(rating: avg) if avg
    end
  end
end
```

- [ ] **Step 7: Add pagination concern**

Create `app/models/concerns/paginatable.rb`:

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

Add `include Paginatable` to `Order` model (in `app/models/order.rb`).

- [ ] **Step 8: Set up routes**

Replace `config/routes.rb`:

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
```

- [ ] **Step 9: Verify routes**

```bash
cd /home/cutalion/code/affordance_test/affordance_order
bin/rails routes
```

- [ ] **Step 10: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add affordance_order/app/controllers affordance_order/config/routes.rb affordance_order/app/models/concerns
git commit -m "feat(order): add API controllers, routes, and pagination"
```

---

### Task 8: Order App — API Request Specs

**Files:**
- Create: `affordance_order/spec/requests/api/clients_spec.rb`
- Create: `affordance_order/spec/requests/api/providers_spec.rb`
- Create: `affordance_order/spec/requests/api/orders_spec.rb`
- Create: `affordance_order/spec/requests/api/cards_spec.rb`
- Create: `affordance_order/spec/requests/api/payments_spec.rb`
- Create: `affordance_order/spec/requests/api/reviews_spec.rb`

- [ ] **Step 1: Write clients request spec**

Create `spec/requests/api/clients_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Api::Clients", type: :request do
  describe "POST /api/clients/register" do
    let(:valid_params) { { client: { email: "new@example.com", name: "New Client", phone: "+79001234567" } } }

    it "creates a client" do
      post "/api/clients/register", params: valid_params
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["email"]).to eq("new@example.com")
      expect(json["api_token"]).to be_present
    end

    it "returns errors for invalid params" do
      post "/api/clients/register", params: { client: { email: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns errors for duplicate email" do
      create(:client, email: "taken@example.com")
      post "/api/clients/register", params: { client: { email: "taken@example.com", name: "Dup" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/clients/me" do
    let(:client) { create(:client) }

    it "returns current client" do
      get "/api/clients/me", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["id"]).to eq(client.id)
    end

    it "returns 401 without token" do
      get "/api/clients/me"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 403 for provider token" do
      provider = create(:provider)
      get "/api/clients/me", headers: auth_headers(provider)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
```

- [ ] **Step 2: Write providers request spec**

Create `spec/requests/api/providers_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Api::Providers", type: :request do
  describe "POST /api/providers/register" do
    let(:valid_params) { { provider: { email: "new@example.com", name: "New Provider", phone: "+79001234567", specialization: "cleaning" } } }

    it "creates a provider" do
      post "/api/providers/register", params: valid_params
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["email"]).to eq("new@example.com")
      expect(json["api_token"]).to be_present
    end

    it "returns errors for invalid params" do
      post "/api/providers/register", params: { provider: { email: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/providers/me" do
    let(:provider) { create(:provider) }

    it "returns current provider" do
      get "/api/providers/me", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["id"]).to eq(provider.id)
    end

    it "returns 401 without token" do
      get "/api/providers/me"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 403 for client token" do
      client = create(:client)
      get "/api/providers/me", headers: auth_headers(client)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
```

- [ ] **Step 3: Write orders request spec**

Create `spec/requests/api/orders_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Api::Orders", type: :request do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }

  describe "GET /api/orders" do
    it "returns client's orders" do
      create(:order, client: client)
      create(:order)

      get "/api/orders", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to eq(1)
    end

    it "returns provider's orders" do
      create(:order, provider: provider)
      create(:order)

      get "/api/orders", headers: auth_headers(provider)
      json = JSON.parse(response.body)
      expect(json.length).to eq(1)
    end

    it "filters by state" do
      create(:order, client: client)
      create(:order, :confirmed, client: client)

      get "/api/orders", params: { state: "confirmed" }, headers: auth_headers(client)
      json = JSON.parse(response.body)
      expect(json.length).to eq(1)
      expect(json.first["state"]).to eq("confirmed")
    end

    it "returns 401 without auth" do
      get "/api/orders"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/orders/:id" do
    let(:order) { create(:order, client: client) }

    it "returns order details" do
      get "/api/orders/#{order.id}", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["id"]).to eq(order.id)
      expect(json).to have_key("notes")
      expect(json).to have_key("payment")
    end

    it "returns 404 for non-existent order" do
      get "/api/orders/999", headers: auth_headers(client)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/orders" do
    let(:order_params) do
      {
        provider_id: provider.id,
        order: {
          scheduled_at: 3.days.from_now,
          duration_minutes: 120,
          location: "123 Main St",
          notes: "Test",
          amount_cents: 350_000,
          currency: "RUB"
        }
      }
    end

    it "creates an order" do
      post "/api/orders", params: order_params, headers: auth_headers(client)
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["state"]).to eq("pending")
      expect(json["client_id"]).to eq(client.id)
    end

    it "returns 403 for provider" do
      post "/api/orders", params: order_params, headers: auth_headers(provider)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 404 for non-existent provider" do
      order_params[:provider_id] = 999
      post "/api/orders", params: order_params, headers: auth_headers(client)
      expect(response).to have_http_status(:not_found)
    end

    it "returns errors for invalid params" do
      order_params[:order][:amount_cents] = nil
      post "/api/orders", params: order_params, headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/orders/:id/confirm" do
    let(:order) { create(:order, provider: provider) }

    it "confirms the order" do
      patch "/api/orders/#{order.id}/confirm", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["state"]).to eq("confirmed")
    end

    it "returns 403 for client" do
      patch "/api/orders/#{order.id}/confirm", headers: auth_headers(client)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns error for wrong provider" do
      other = create(:provider)
      patch "/api/orders/#{order.id}/confirm", headers: auth_headers(other)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/orders/:id/start" do
    let(:order) { create(:order, :confirmed, provider: provider) }

    it "starts the order" do
      patch "/api/orders/#{order.id}/start", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["state"]).to eq("in_progress")
    end

    it "returns error for pending order" do
      pending_order = create(:order, provider: provider)
      patch "/api/orders/#{pending_order.id}/start", headers: auth_headers(provider)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/orders/:id/complete" do
    let(:order) { create(:order, :in_progress, provider: provider) }

    it "completes the order" do
      patch "/api/orders/#{order.id}/complete", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["state"]).to eq("completed")
    end
  end

  describe "PATCH /api/orders/:id/cancel" do
    let(:order) { create(:order, client: client) }

    it "cancels the order" do
      patch "/api/orders/#{order.id}/cancel", params: { reason: "Changed plans" }, headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["state"]).to eq("canceled")
    end

    it "returns error without reason" do
      patch "/api/orders/#{order.id}/cancel", headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 403 for provider" do
      patch "/api/orders/#{order.id}/cancel", params: { reason: "x" }, headers: auth_headers(provider)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /api/orders/:id/reject" do
    let(:order) { create(:order, :confirmed, provider: provider) }

    it "rejects the order" do
      patch "/api/orders/#{order.id}/reject", params: { reason: "Not available" }, headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["state"]).to eq("rejected")
    end

    it "returns error without reason" do
      patch "/api/orders/#{order.id}/reject", headers: auth_headers(provider)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
```

- [ ] **Step 4: Write cards request spec**

Create `spec/requests/api/cards_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Api::Cards", type: :request do
  let(:client) { create(:client) }

  describe "GET /api/cards" do
    it "returns client's cards" do
      create(:card, client: client)
      get "/api/cards", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to eq(1)
    end

    it "returns 403 for provider" do
      provider = create(:provider)
      get "/api/cards", headers: auth_headers(provider)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/cards" do
    let(:card_params) { { card: { token: "tok_test123", last_four: "4242", brand: "visa", exp_month: 12, exp_year: 2028 } } }

    it "creates a card" do
      post "/api/cards", params: card_params, headers: auth_headers(client)
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["last_four"]).to eq("4242")
    end

    it "sets first card as default" do
      post "/api/cards", params: card_params, headers: auth_headers(client)
      expect(client.cards.first).to be_default
    end

    it "returns errors for invalid params" do
      post "/api/cards", params: { card: { token: "" } }, headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/cards/:id" do
    it "deletes the card" do
      card = create(:card, client: client)
      delete "/api/cards/#{card.id}", headers: auth_headers(client)
      expect(response).to have_http_status(:no_content)
      expect(Card.find_by(id: card.id)).to be_nil
    end

    it "returns 404 for other client's card" do
      card = create(:card)
      delete "/api/cards/#{card.id}", headers: auth_headers(client)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/cards/:id/default" do
    it "sets card as default" do
      card1 = create(:card, client: client, default: true)
      card2 = create(:card, client: client, default: false)
      patch "/api/cards/#{card2.id}/default", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      expect(card2.reload).to be_default
      expect(card1.reload).not_to be_default
    end
  end
end
```

- [ ] **Step 5: Write payments request spec**

Create `spec/requests/api/payments_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Api::Payments", type: :request do
  let(:client) { create(:client) }
  let(:order) { create(:order, client: client) }

  describe "GET /api/payments" do
    it "returns client's payments" do
      create(:payment, order: order)
      create(:payment)

      get "/api/payments", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to eq(1)
    end

    it "filters by status" do
      create(:payment, order: order)
      create(:payment, :held, order: create(:order, client: client))

      get "/api/payments", params: { status: "held" }, headers: auth_headers(client)
      json = JSON.parse(response.body)
      expect(json.length).to eq(1)
      expect(json.first["status"]).to eq("held")
    end
  end

  describe "GET /api/payments/:id" do
    it "returns payment details" do
      payment = create(:payment, order: order)
      get "/api/payments/#{payment.id}", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["id"]).to eq(payment.id)
    end

    it "returns 403 for other user's payment" do
      other_payment = create(:payment)
      get "/api/payments/#{other_payment.id}", headers: auth_headers(client)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
```

- [ ] **Step 6: Write reviews request spec**

Create `spec/requests/api/reviews_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Api::Reviews", type: :request do
  let(:client) { create(:client) }
  let(:order) { create(:order, :completed, client: client) }

  describe "GET /api/orders/:order_id/reviews" do
    it "returns reviews for order" do
      create(:review, order: order, author: client)
      get "/api/orders/#{order.id}/reviews", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to eq(1)
    end
  end

  describe "POST /api/orders/:order_id/reviews" do
    it "creates a review" do
      post "/api/orders/#{order.id}/reviews",
        params: { rating: 5, body: "Great!" },
        headers: auth_headers(client)
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["rating"]).to eq(5)
    end

    it "updates provider rating" do
      post "/api/orders/#{order.id}/reviews",
        params: { rating: 4, body: "Good" },
        headers: auth_headers(client)
      expect(order.provider.reload.rating.to_f).to eq(4.0)
    end

    it "returns errors for invalid rating" do
      post "/api/orders/#{order.id}/reviews",
        params: { rating: 6 },
        headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "prevents duplicate reviews" do
      create(:review, order: order, author: client)
      post "/api/orders/#{order.id}/reviews",
        params: { rating: 5 },
        headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "prevents review on non-completed order" do
      pending_order = create(:order, client: client)
      post "/api/orders/#{pending_order.id}/reviews",
        params: { rating: 5 },
        headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "allows provider to review" do
      post "/api/orders/#{order.id}/reviews",
        params: { rating: 5, body: "Great client!" },
        headers: auth_headers(order.provider)
      expect(response).to have_http_status(:created)
    end
  end
end
```

- [ ] **Step 7: Run all request specs**

```bash
cd /home/cutalion/code/affordance_test/affordance_order
bundle exec rspec spec/requests
```

- [ ] **Step 8: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add affordance_order/spec/requests
git commit -m "feat(order): add API request specs"
```

---

### Task 9: Order App — Background Jobs

**Files:**
- Create: `affordance_order/app/jobs/payment_hold_job.rb`
- Create: `affordance_order/app/jobs/review_reminder_job.rb`
- Create: `affordance_order/spec/jobs/payment_hold_job_spec.rb`
- Create: `affordance_order/spec/jobs/review_reminder_job_spec.rb`

- [ ] **Step 1: Create PaymentHoldJob**

Create `app/jobs/payment_hold_job.rb`:

```ruby
class PaymentHoldJob < ApplicationJob
  queue_as :default

  def perform
    orders = Order.where(state: %w[pending confirmed])
                  .where("scheduled_at BETWEEN ? AND ?", Time.current, 1.day.from_now)
                  .includes(:payment, client: :cards)

    orders.find_each do |order|
      next unless order.payment&.status == "pending"

      result = PaymentGateway.hold(order.payment)
      Rails.logger.info "[PaymentHoldJob] order_id=#{order.id} success=#{result[:success]} error=#{result[:error]}"
    end
  end
end
```

- [ ] **Step 2: Create ReviewReminderJob**

Create `app/jobs/review_reminder_job.rb`:

```ruby
class ReviewReminderJob < ApplicationJob
  queue_as :default

  def perform
    orders = Order.where(state: "completed")
                  .where("completed_at < ?", 24.hours.ago)
                  .where("completed_at > ?", 48.hours.ago)
                  .includes(:reviews, :client, :provider)

    orders.find_each do |order|
      remind_client(order) unless order.reviews.exists?(author: order.client)
      remind_provider(order) unless order.reviews.exists?(author: order.provider)
    end
  end

  private

  def remind_client(order)
    NotificationService.notify(order.client, :review_reminder, order_id: order.id)
  end

  def remind_provider(order)
    NotificationService.notify(order.provider, :review_reminder, order_id: order.id)
  end
end
```

- [ ] **Step 3: Write job specs**

Create `spec/jobs/payment_hold_job_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe PaymentHoldJob, type: :job do
  describe "#perform" do
    let(:client) { create(:client) }
    let!(:card) { create(:card, client: client, default: true) }

    it "holds payments for orders scheduled tomorrow" do
      order = create(:order, client: client, scheduled_at: 20.hours.from_now)
      payment = create(:payment, order: order, status: "pending")

      described_class.new.perform

      expect(payment.reload.status).to eq("held")
    end

    it "skips orders scheduled later than 1 day" do
      order = create(:order, client: client, scheduled_at: 3.days.from_now)
      payment = create(:payment, order: order, status: "pending")

      described_class.new.perform

      expect(payment.reload.status).to eq("pending")
    end

    it "skips already-held payments" do
      order = create(:order, client: client, scheduled_at: 20.hours.from_now)
      create(:payment, :held, order: order, card: card)

      expect { described_class.new.perform }.not_to raise_error
    end

    it "skips canceled orders" do
      order = create(:order, :canceled, client: client, scheduled_at: 20.hours.from_now)
      payment = create(:payment, order: order, status: "pending")

      described_class.new.perform

      expect(payment.reload.status).to eq("pending")
    end

    it "handles orders without default card" do
      card.update!(default: false)
      order = create(:order, client: client, scheduled_at: 20.hours.from_now)
      create(:payment, order: order, status: "pending")

      expect { described_class.new.perform }.not_to raise_error
    end
  end
end
```

Create `spec/jobs/review_reminder_job_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ReviewReminderJob, type: :job do
  describe "#perform" do
    it "sends reminders for orders completed 24-48 hours ago" do
      order = create(:order, :completed, completed_at: 30.hours.ago)

      described_class.new.perform

      log = read_notification_log
      expect(log).to include("event=review_reminder")
    end

    it "sends to both client and provider" do
      order = create(:order, :completed, completed_at: 30.hours.ago)

      described_class.new.perform

      log = read_notification_log
      expect(log).to include("to=client_#{order.client_id}")
      expect(log).to include("to=provider_#{order.provider_id}")
    end

    it "skips if review already exists" do
      order = create(:order, :completed, completed_at: 30.hours.ago)
      create(:review, order: order, author: order.client)

      described_class.new.perform

      log = read_notification_log
      expect(log).not_to include("to=client_#{order.client_id}")
      expect(log).to include("to=provider_#{order.provider_id}")
    end

    it "skips orders completed less than 24 hours ago" do
      create(:order, :completed, completed_at: 12.hours.ago)

      described_class.new.perform

      log = read_notification_log
      expect(log).to be_empty
    end

    it "skips orders completed more than 48 hours ago" do
      create(:order, :completed, completed_at: 72.hours.ago)

      described_class.new.perform

      log = read_notification_log
      expect(log).to be_empty
    end
  end
end
```

- [ ] **Step 4: Run job specs**

```bash
cd /home/cutalion/code/affordance_test/affordance_order
bundle exec rspec spec/jobs
```

- [ ] **Step 5: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add affordance_order/app/jobs affordance_order/spec/jobs
git commit -m "feat(order): add PaymentHoldJob and ReviewReminderJob with specs"
```

---

### Task 10: Order App — Admin Interface

**Files:**
- Create: `affordance_order/app/controllers/admin/base_controller.rb`
- Create: `affordance_order/app/controllers/admin/dashboard_controller.rb`
- Create: `affordance_order/app/controllers/admin/orders_controller.rb`
- Create: `affordance_order/app/controllers/admin/clients_controller.rb`
- Create: `affordance_order/app/controllers/admin/providers_controller.rb`
- Create: `affordance_order/app/controllers/admin/payments_controller.rb`
- Create: `affordance_order/app/views/layouts/admin.html.erb`
- Create: `affordance_order/app/views/admin/dashboard/index.html.erb`
- Create: `affordance_order/app/views/admin/orders/index.html.erb`
- Create: `affordance_order/app/views/admin/orders/show.html.erb`
- Create: `affordance_order/app/views/admin/clients/index.html.erb`
- Create: `affordance_order/app/views/admin/clients/show.html.erb`
- Create: `affordance_order/app/views/admin/providers/index.html.erb`
- Create: `affordance_order/app/views/admin/providers/show.html.erb`
- Create: `affordance_order/app/views/admin/payments/index.html.erb`
- Create: `affordance_order/app/views/admin/payments/show.html.erb`
- Modify: `affordance_order/config/routes.rb`

- [ ] **Step 1: Create admin base controller**

Create `app/controllers/admin/base_controller.rb`:

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

- [ ] **Step 2: Create admin controllers**

Create `app/controllers/admin/dashboard_controller.rb`:

```ruby
module Admin
  class DashboardController < BaseController
    def index
      @orders_by_state = Order.group(:state).count
      @total_revenue = Payment.where(status: "charged").sum(:amount_cents)
      @total_fees = Payment.where(status: "charged").sum(:fee_cents)
      @recent_orders = Order.sorted.limit(10).includes(:client, :provider)
      @client_count = Client.count
      @provider_count = Provider.count
    end
  end
end
```

Create `app/controllers/admin/orders_controller.rb`:

```ruby
module Admin
  class OrdersController < BaseController
    def index
      @orders = Order.includes(:client, :provider)
                     .by_state(params[:state])
                     .by_client(params[:client_id])
                     .by_provider(params[:provider_id])
                     .scheduled_between(params[:from], params[:to])
                     .sorted

      @orders = paginate(@orders)
    end

    def show
      @order = Order.includes(:payment, :reviews, :client, :provider).find(params[:id])
    end
  end
end
```

Create `app/controllers/admin/clients_controller.rb`:

```ruby
module Admin
  class ClientsController < BaseController
    def index
      @clients = paginate(Client.order(created_at: :desc))
    end

    def show
      @client = Client.find(params[:id])
      @orders = @client.orders.sorted.limit(20)
      @cards = @client.cards
    end
  end
end
```

Create `app/controllers/admin/providers_controller.rb`:

```ruby
module Admin
  class ProvidersController < BaseController
    def index
      @providers = paginate(Provider.order(created_at: :desc))
    end

    def show
      @provider = Provider.find(params[:id])
      @orders = @provider.orders.sorted.limit(20)
    end
  end
end
```

Create `app/controllers/admin/payments_controller.rb`:

```ruby
module Admin
  class PaymentsController < BaseController
    def index
      @payments = Payment.includes(order: [:client, :provider])
                         .by_status(params[:status])
                         .order(created_at: :desc)
      @payments = paginate(@payments)
    end

    def show
      @payment = Payment.includes(order: [:client, :provider]).find(params[:id])
    end
  end
end
```

- [ ] **Step 3: Create admin layout**

Create `app/views/layouts/admin.html.erb`:

```erb
<!DOCTYPE html>
<html>
<head>
  <title>Admin - Service Market</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 0; background: #f5f5f5; color: #333; }
    nav { background: #2c3e50; padding: 12px 24px; display: flex; gap: 20px; }
    nav a { color: #ecf0f1; text-decoration: none; font-size: 14px; }
    nav a:hover { color: #3498db; }
    .container { max-width: 1200px; margin: 0 auto; padding: 24px; }
    h1 { font-size: 24px; margin-bottom: 16px; }
    h2 { font-size: 18px; margin-bottom: 12px; }
    table { width: 100%; border-collapse: collapse; background: white; margin-bottom: 20px; }
    th, td { padding: 10px 12px; text-align: left; border-bottom: 1px solid #eee; font-size: 14px; }
    th { background: #f8f9fa; font-weight: 600; }
    tr:hover { background: #f8f9fa; }
    a { color: #3498db; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .stat-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 16px; margin-bottom: 24px; }
    .stat-card { background: white; padding: 16px; border-radius: 4px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
    .stat-card .value { font-size: 24px; font-weight: bold; }
    .stat-card .label { font-size: 12px; color: #666; margin-top: 4px; }
    .filters { background: white; padding: 16px; margin-bottom: 20px; border-radius: 4px; display: flex; gap: 12px; align-items: end; flex-wrap: wrap; }
    .filters label { font-size: 12px; color: #666; display: block; margin-bottom: 4px; }
    .filters input, .filters select { padding: 6px 10px; border: 1px solid #ddd; border-radius: 4px; font-size: 14px; }
    .filters button { padding: 6px 16px; background: #3498db; color: white; border: none; border-radius: 4px; cursor: pointer; }
    .badge { display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 12px; font-weight: 600; }
    .badge-pending { background: #ffeaa7; color: #856404; }
    .badge-confirmed { background: #81ecec; color: #00695c; }
    .badge-in_progress { background: #74b9ff; color: #004085; }
    .badge-completed { background: #55efc4; color: #155724; }
    .badge-canceled { background: #fab1a0; color: #721c24; }
    .badge-rejected { background: #fd79a8; color: #721c24; }
    .detail-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }
    .detail-card { background: white; padding: 20px; border-radius: 4px; }
    .detail-row { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #f0f0f0; }
    .detail-row .label { color: #666; font-size: 13px; }
    .pagination { margin-top: 16px; display: flex; gap: 8px; }
    .pagination a { padding: 6px 12px; background: white; border: 1px solid #ddd; border-radius: 4px; }
  </style>
</head>
<body>
  <nav>
    <a href="/admin/dashboard">Dashboard</a>
    <a href="/admin/orders">Orders</a>
    <a href="/admin/clients">Clients</a>
    <a href="/admin/providers">Providers</a>
    <a href="/admin/payments">Payments</a>
  </nav>
  <div class="container">
    <%= yield %>
  </div>
</body>
</html>
```

- [ ] **Step 4: Create admin views**

Create `app/views/admin/dashboard/index.html.erb`:

```erb
<h1>Dashboard</h1>

<div class="stat-grid">
  <div class="stat-card">
    <div class="value"><%= @client_count %></div>
    <div class="label">Clients</div>
  </div>
  <div class="stat-card">
    <div class="value"><%= @provider_count %></div>
    <div class="label">Providers</div>
  </div>
  <div class="stat-card">
    <div class="value"><%= number_to_currency(@total_revenue / 100.0, unit: "RUB ") %></div>
    <div class="label">Total Revenue</div>
  </div>
  <div class="stat-card">
    <div class="value"><%= number_to_currency(@total_fees / 100.0, unit: "RUB ") %></div>
    <div class="label">Total Fees</div>
  </div>
  <% @orders_by_state.each do |state, count| %>
    <div class="stat-card">
      <div class="value"><%= count %></div>
      <div class="label">Orders: <%= state %></div>
    </div>
  <% end %>
</div>

<h2>Recent Orders</h2>
<table>
  <thead>
    <tr><th>ID</th><th>Client</th><th>Provider</th><th>State</th><th>Scheduled</th><th>Amount</th></tr>
  </thead>
  <tbody>
    <% @recent_orders.each do |order| %>
      <tr>
        <td><a href="/admin/orders/<%= order.id %>"><%= order.id %></a></td>
        <td><%= order.client.name %></td>
        <td><%= order.provider.name %></td>
        <td><span class="badge badge-<%= order.state %>"><%= order.state %></span></td>
        <td><%= order.scheduled_at&.strftime("%Y-%m-%d %H:%M") %></td>
        <td><%= order.amount_cents / 100.0 %> <%= order.currency %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

Create `app/views/admin/orders/index.html.erb`:

```erb
<h1>Orders</h1>

<div class="filters">
  <%= form_tag("/admin/orders", method: :get) do %>
    <div>
      <%= label_tag :state, "State" %>
      <%= select_tag :state, options_for_select(%w[pending confirmed in_progress completed canceled rejected], params[:state]), include_blank: "All" %>
    </div>
    <div>
      <%= label_tag :from, "From" %>
      <%= date_field_tag :from, params[:from] %>
    </div>
    <div>
      <%= label_tag :to, "To" %>
      <%= date_field_tag :to, params[:to] %>
    </div>
    <button type="submit">Filter</button>
  <% end %>
</div>

<table>
  <thead>
    <tr><th>ID</th><th>Client</th><th>Provider</th><th>State</th><th>Scheduled</th><th>Amount</th><th>Created</th></tr>
  </thead>
  <tbody>
    <% @orders.each do |order| %>
      <tr>
        <td><a href="/admin/orders/<%= order.id %>"><%= order.id %></a></td>
        <td><a href="/admin/clients/<%= order.client_id %>"><%= order.client.name %></a></td>
        <td><a href="/admin/providers/<%= order.provider_id %>"><%= order.provider.name %></a></td>
        <td><span class="badge badge-<%= order.state %>"><%= order.state %></span></td>
        <td><%= order.scheduled_at&.strftime("%Y-%m-%d %H:%M") %></td>
        <td><%= order.amount_cents / 100.0 %> <%= order.currency %></td>
        <td><%= order.created_at.strftime("%Y-%m-%d") %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

Create `app/views/admin/orders/show.html.erb`:

```erb
<h1>Order #<%= @order.id %></h1>

<div class="detail-grid">
  <div class="detail-card">
    <h2>Details</h2>
    <div class="detail-row"><span class="label">State</span><span class="badge badge-<%= @order.state %>"><%= @order.state %></span></div>
    <div class="detail-row"><span class="label">Client</span><a href="/admin/clients/<%= @order.client_id %>"><%= @order.client.name %></a></div>
    <div class="detail-row"><span class="label">Provider</span><a href="/admin/providers/<%= @order.provider_id %>"><%= @order.provider.name %></a></div>
    <div class="detail-row"><span class="label">Scheduled</span><span><%= @order.scheduled_at&.strftime("%Y-%m-%d %H:%M") %></span></div>
    <div class="detail-row"><span class="label">Duration</span><span><%= @order.duration_minutes %> min</span></div>
    <div class="detail-row"><span class="label">Location</span><span><%= @order.location %></span></div>
    <div class="detail-row"><span class="label">Amount</span><span><%= @order.amount_cents / 100.0 %> <%= @order.currency %></span></div>
    <div class="detail-row"><span class="label">Notes</span><span><%= @order.notes %></span></div>
    <% if @order.cancel_reason.present? %>
      <div class="detail-row"><span class="label">Cancel Reason</span><span><%= @order.cancel_reason %></span></div>
    <% end %>
    <% if @order.reject_reason.present? %>
      <div class="detail-row"><span class="label">Reject Reason</span><span><%= @order.reject_reason %></span></div>
    <% end %>
    <div class="detail-row"><span class="label">Started At</span><span><%= @order.started_at&.strftime("%Y-%m-%d %H:%M") %></span></div>
    <div class="detail-row"><span class="label">Completed At</span><span><%= @order.completed_at&.strftime("%Y-%m-%d %H:%M") %></span></div>
    <div class="detail-row"><span class="label">Created At</span><span><%= @order.created_at.strftime("%Y-%m-%d %H:%M") %></span></div>
  </div>

  <div class="detail-card">
    <h2>Payment</h2>
    <% if @order.payment %>
      <div class="detail-row"><span class="label">Status</span><span><%= @order.payment.status %></span></div>
      <div class="detail-row"><span class="label">Amount</span><span><%= @order.payment.amount_cents / 100.0 %> <%= @order.payment.currency %></span></div>
      <div class="detail-row"><span class="label">Fee</span><span><%= @order.payment.fee_cents / 100.0 %> <%= @order.payment.currency %></span></div>
      <div class="detail-row"><span class="label">Card</span><span><%= @order.payment.card&.then { |c| "*#{c.last_four} #{c.brand}" } || "N/A" %></span></div>
    <% else %>
      <p>No payment</p>
    <% end %>

    <h2>Reviews</h2>
    <% @order.reviews.each do |review| %>
      <div class="detail-row">
        <span class="label"><%= review.author_type %> (<%= review.rating %>/5)</span>
        <span><%= review.body %></span>
      </div>
    <% end %>
    <% if @order.reviews.empty? %>
      <p>No reviews yet</p>
    <% end %>
  </div>
</div>
```

Create `app/views/admin/clients/index.html.erb`:

```erb
<h1>Clients</h1>
<table>
  <thead>
    <tr><th>ID</th><th>Name</th><th>Email</th><th>Phone</th><th>Registered</th></tr>
  </thead>
  <tbody>
    <% @clients.each do |client| %>
      <tr>
        <td><a href="/admin/clients/<%= client.id %>"><%= client.id %></a></td>
        <td><%= client.name %></td>
        <td><%= client.email %></td>
        <td><%= client.phone %></td>
        <td><%= client.created_at.strftime("%Y-%m-%d") %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

Create `app/views/admin/clients/show.html.erb`:

```erb
<h1>Client: <%= @client.name %></h1>
<div class="detail-card" style="margin-bottom: 20px;">
  <div class="detail-row"><span class="label">Email</span><span><%= @client.email %></span></div>
  <div class="detail-row"><span class="label">Phone</span><span><%= @client.phone %></span></div>
  <div class="detail-row"><span class="label">Registered</span><span><%= @client.created_at.strftime("%Y-%m-%d %H:%M") %></span></div>
  <div class="detail-row"><span class="label">Cards</span><span><%= @cards.count %></span></div>
</div>

<h2>Recent Orders</h2>
<table>
  <thead>
    <tr><th>ID</th><th>State</th><th>Provider</th><th>Scheduled</th><th>Amount</th></tr>
  </thead>
  <tbody>
    <% @orders.each do |order| %>
      <tr>
        <td><a href="/admin/orders/<%= order.id %>"><%= order.id %></a></td>
        <td><span class="badge badge-<%= order.state %>"><%= order.state %></span></td>
        <td><%= order.provider.name %></td>
        <td><%= order.scheduled_at&.strftime("%Y-%m-%d %H:%M") %></td>
        <td><%= order.amount_cents / 100.0 %> <%= order.currency %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

Create `app/views/admin/providers/index.html.erb`:

```erb
<h1>Providers</h1>
<table>
  <thead>
    <tr><th>ID</th><th>Name</th><th>Email</th><th>Specialization</th><th>Rating</th><th>Active</th></tr>
  </thead>
  <tbody>
    <% @providers.each do |provider| %>
      <tr>
        <td><a href="/admin/providers/<%= provider.id %>"><%= provider.id %></a></td>
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

Create `app/views/admin/providers/show.html.erb`:

```erb
<h1>Provider: <%= @provider.name %></h1>
<div class="detail-card" style="margin-bottom: 20px;">
  <div class="detail-row"><span class="label">Email</span><span><%= @provider.email %></span></div>
  <div class="detail-row"><span class="label">Phone</span><span><%= @provider.phone %></span></div>
  <div class="detail-row"><span class="label">Specialization</span><span><%= @provider.specialization %></span></div>
  <div class="detail-row"><span class="label">Rating</span><span><%= @provider.rating %></span></div>
  <div class="detail-row"><span class="label">Active</span><span><%= @provider.active? ? "Yes" : "No" %></span></div>
</div>

<h2>Recent Orders</h2>
<table>
  <thead>
    <tr><th>ID</th><th>State</th><th>Client</th><th>Scheduled</th><th>Amount</th></tr>
  </thead>
  <tbody>
    <% @orders.each do |order| %>
      <tr>
        <td><a href="/admin/orders/<%= order.id %>"><%= order.id %></a></td>
        <td><span class="badge badge-<%= order.state %>"><%= order.state %></span></td>
        <td><%= order.client.name %></td>
        <td><%= order.scheduled_at&.strftime("%Y-%m-%d %H:%M") %></td>
        <td><%= order.amount_cents / 100.0 %> <%= order.currency %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

Create `app/views/admin/payments/index.html.erb`:

```erb
<h1>Payments</h1>

<div class="filters">
  <%= form_tag("/admin/payments", method: :get) do %>
    <div>
      <%= label_tag :status, "Status" %>
      <%= select_tag :status, options_for_select(%w[pending held charged refunded], params[:status]), include_blank: "All" %>
    </div>
    <button type="submit">Filter</button>
  <% end %>
</div>

<table>
  <thead>
    <tr><th>ID</th><th>Order</th><th>Client</th><th>Amount</th><th>Fee</th><th>Status</th><th>Created</th></tr>
  </thead>
  <tbody>
    <% @payments.each do |payment| %>
      <tr>
        <td><a href="/admin/payments/<%= payment.id %>"><%= payment.id %></a></td>
        <td><a href="/admin/orders/<%= payment.order_id %>"><%= payment.order_id %></a></td>
        <td><%= payment.order.client.name %></td>
        <td><%= payment.amount_cents / 100.0 %> <%= payment.currency %></td>
        <td><%= payment.fee_cents / 100.0 %></td>
        <td><%= payment.status %></td>
        <td><%= payment.created_at.strftime("%Y-%m-%d") %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

Create `app/views/admin/payments/show.html.erb`:

```erb
<h1>Payment #<%= @payment.id %></h1>
<div class="detail-card">
  <div class="detail-row"><span class="label">Order</span><a href="/admin/orders/<%= @payment.order_id %>">#<%= @payment.order_id %></a></div>
  <div class="detail-row"><span class="label">Client</span><a href="/admin/clients/<%= @payment.order.client_id %>"><%= @payment.order.client.name %></a></div>
  <div class="detail-row"><span class="label">Amount</span><span><%= @payment.amount_cents / 100.0 %> <%= @payment.currency %></span></div>
  <div class="detail-row"><span class="label">Fee</span><span><%= @payment.fee_cents / 100.0 %> <%= @payment.currency %></span></div>
  <div class="detail-row"><span class="label">Status</span><span><%= @payment.status %></span></div>
  <div class="detail-row"><span class="label">Card</span><span><%= @payment.card&.then { |c| "*#{c.last_four} #{c.brand}" } || "N/A" %></span></div>
  <div class="detail-row"><span class="label">Held At</span><span><%= @payment.held_at&.strftime("%Y-%m-%d %H:%M") %></span></div>
  <div class="detail-row"><span class="label">Charged At</span><span><%= @payment.charged_at&.strftime("%Y-%m-%d %H:%M") %></span></div>
  <div class="detail-row"><span class="label">Refunded At</span><span><%= @payment.refunded_at&.strftime("%Y-%m-%d %H:%M") %></span></div>
</div>
```

- [ ] **Step 5: Update routes for admin**

Add to `config/routes.rb` (inside the draw block, before the health check):

```ruby
  namespace :admin do
    get "/", to: "dashboard#index"
    get "dashboard", to: "dashboard#index"
    resources :orders, only: [:index, :show]
    resources :clients, only: [:index, :show]
    resources :providers, only: [:index, :show]
    resources :payments, only: [:index, :show]
  end
```

- [ ] **Step 6: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add affordance_order/app/controllers/admin affordance_order/app/views affordance_order/config/routes.rb
git commit -m "feat(order): add admin interface - dashboard, orders, clients, providers, payments"
```

---

### Task 11: Order App — Admin Request Specs

**Files:**
- Create: `affordance_order/spec/requests/admin/dashboard_spec.rb`
- Create: `affordance_order/spec/requests/admin/orders_spec.rb`
- Create: `affordance_order/spec/requests/admin/clients_spec.rb`
- Create: `affordance_order/spec/requests/admin/providers_spec.rb`
- Create: `affordance_order/spec/requests/admin/payments_spec.rb`

- [ ] **Step 1: Write admin specs**

Create `spec/requests/admin/dashboard_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Admin::Dashboard", type: :request do
  describe "GET /admin/dashboard" do
    it "requires authentication" do
      get "/admin/dashboard"
      expect(response).to have_http_status(:unauthorized)
    end

    it "renders dashboard with stats" do
      create(:order, :completed)
      create(:payment, :charged)

      get "/admin/dashboard", headers: admin_auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dashboard")
    end
  end
end
```

Create `spec/requests/admin/orders_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Admin::Orders", type: :request do
  describe "GET /admin/orders" do
    it "requires authentication" do
      get "/admin/orders"
      expect(response).to have_http_status(:unauthorized)
    end

    it "lists orders" do
      create(:order)
      get "/admin/orders", headers: admin_auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Orders")
    end

    it "filters by state" do
      create(:order)
      confirmed = create(:order, :confirmed)

      get "/admin/orders", params: { state: "confirmed" }, headers: admin_auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("confirmed")
    end
  end

  describe "GET /admin/orders/:id" do
    it "shows order details" do
      order = create(:order)
      get "/admin/orders/#{order.id}", headers: admin_auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Order ##{order.id}")
    end
  end
end
```

Create `spec/requests/admin/clients_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Admin::Clients", type: :request do
  describe "GET /admin/clients" do
    it "requires authentication" do
      get "/admin/clients"
      expect(response).to have_http_status(:unauthorized)
    end

    it "lists clients" do
      create(:client, name: "Alice")
      get "/admin/clients", headers: admin_auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Alice")
    end
  end

  describe "GET /admin/clients/:id" do
    it "shows client details" do
      client = create(:client, name: "Bob")
      get "/admin/clients/#{client.id}", headers: admin_auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Bob")
    end
  end
end
```

Create `spec/requests/admin/providers_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Admin::Providers", type: :request do
  describe "GET /admin/providers" do
    it "requires authentication" do
      get "/admin/providers"
      expect(response).to have_http_status(:unauthorized)
    end

    it "lists providers" do
      create(:provider, name: "Charlie")
      get "/admin/providers", headers: admin_auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Charlie")
    end
  end

  describe "GET /admin/providers/:id" do
    it "shows provider details" do
      provider = create(:provider, name: "Dave")
      get "/admin/providers/#{provider.id}", headers: admin_auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dave")
    end
  end
end
```

Create `spec/requests/admin/payments_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Admin::Payments", type: :request do
  describe "GET /admin/payments" do
    it "requires authentication" do
      get "/admin/payments"
      expect(response).to have_http_status(:unauthorized)
    end

    it "lists payments" do
      create(:payment)
      get "/admin/payments", headers: admin_auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Payments")
    end

    it "filters by status" do
      create(:payment, :held)
      get "/admin/payments", params: { status: "held" }, headers: admin_auth_headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /admin/payments/:id" do
    it "shows payment details" do
      payment = create(:payment)
      get "/admin/payments/#{payment.id}", headers: admin_auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Payment ##{payment.id}")
    end
  end
end
```

- [ ] **Step 2: Run all specs**

```bash
cd /home/cutalion/code/affordance_test/affordance_order
bundle exec rspec
```

Expected: All pass

- [ ] **Step 3: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add affordance_order/spec/requests/admin
git commit -m "feat(order): add admin request specs"
```

---

### Task 12: Create Request App from Order App

Copy the Order app and adapt it for the Request naming with legacy invitation-era states.

**This is the largest task. Every file that references "order" must be adapted to "request" with the additional legacy states and services.**

- [ ] **Step 1: Copy the Order app**

```bash
cd /home/cutalion/code/affordance_test
cp -r affordance_order affordance_request
```

- [ ] **Step 2: Rename and adapt the Request model**

Replace `affordance_request/app/models/order.rb` → `affordance_request/app/models/request.rb`:

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
    state :created, initial: true
    state :created_accepted
    state :accepted
    state :started
    state :fulfilled
    state :declined
    state :missed
    state :canceled
    state :rejected

    event :accept do
      transitions from: :created, to: :accepted
    end

    event :decline do
      transitions from: :created, to: :declined
    end

    event :miss do
      transitions from: :created, to: :missed
    end

    event :start do
      transitions from: [:accepted, :created_accepted], to: :started
      after do
        update!(started_at: Time.current)
      end
    end

    event :fulfill do
      transitions from: :started, to: :fulfilled
      after do
        update!(completed_at: Time.current)
      end
    end

    event :cancel do
      transitions from: [:created, :accepted, :created_accepted], to: :canceled
    end

    event :reject do
      transitions from: [:accepted, :created_accepted, :started], to: :rejected
    end
  end
end
```

- [ ] **Step 3: Update migrations — rename table to requests**

Edit the create_orders migration file: change `create_table :orders` to `create_table :requests`, change index names accordingly.

Edit create_payments migration: change `t.references :order` to `t.references :request`, and the foreign key.

Edit create_reviews migration: change `t.references :order` to `t.references :request`, and indexes.

- [ ] **Step 4: Update Payment model**

In `affordance_request/app/models/payment.rb`:
- Change `belongs_to :order` → `belongs_to :request`
- Change scope `pending_holds` to join `:requests` table instead of `:orders`
- Change all references from `order` to `request`

```ruby
class Payment < ApplicationRecord
  belongs_to :request
  belongs_to :card, optional: true

  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending held charged refunded] }

  scope :by_status, ->(status) { where(status: status) if status.present? }
  scope :pending_holds, -> {
    where(status: "pending")
      .joins(:request)
      .where("requests.scheduled_at BETWEEN ? AND ?", Time.current, 1.day.from_now)
  }

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

- [ ] **Step 5: Update Review model**

In `affordance_request/app/models/review.rb`:
- Change `belongs_to :order` → `belongs_to :request`
- Change `order_must_be_completed` to check `request.fulfilled?` instead of `request.completed?`

```ruby
class Review < ApplicationRecord
  belongs_to :request
  belongs_to :author, polymorphic: true

  validates :rating, presence: true, numericality: { in: 1..5 }
  validates :author_type, inclusion: { in: %w[Client Provider] }
  validates :request_id, uniqueness: { scope: [:author_type, :author_id], message: "already reviewed by this author" }
  validate :request_must_be_fulfilled

  private

  def request_must_be_fulfilled
    return if request.nil?
    unless request.fulfilled?
      errors.add(:request, "must be fulfilled before reviewing")
    end
  end
end
```

- [ ] **Step 6: Update Client model**

Change `has_many :orders` → `has_many :requests`

- [ ] **Step 7: Update Provider model**

Change `has_many :orders` → `has_many :requests`

- [ ] **Step 8: Update services — rename and add legacy services**

Delete `affordance_request/app/services/orders/` directory. Create `affordance_request/app/services/requests/` with these files:

Create `app/services/requests/create_service.rb`:

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
        notes: @params[:notes],
        amount_cents: @params[:amount_cents],
        currency: @params[:currency] || "RUB"
      )

      Request.transaction do
        request.save!
        Payment.create!(
          request: request,
          amount_cents: request.amount_cents,
          currency: request.currency,
          fee_cents: calculate_fee(request.amount_cents),
          status: "pending"
        )
      end

      NotificationService.notify(@provider, :request_created, request_id: request.id)
      { success: true, request: request }
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

Create `app/services/requests/create_accepted_service.rb`:

```ruby
module Requests
  class CreateAcceptedService
    def initialize(provider:, client:, params:)
      @provider = provider
      @client = client
      @params = params
    end

    def call
      request = Request.new(
        client: @client,
        provider: @provider,
        state: "created_accepted",
        scheduled_at: @params[:scheduled_at],
        duration_minutes: @params[:duration_minutes],
        location: @params[:location],
        notes: @params[:notes],
        amount_cents: @params[:amount_cents],
        currency: @params[:currency] || "RUB"
      )

      Request.transaction do
        request.save!
        Payment.create!(
          request: request,
          amount_cents: request.amount_cents,
          currency: request.currency,
          fee_cents: calculate_fee(request.amount_cents),
          status: "pending"
        )
      end

      NotificationService.notify(@client, :request_created_accepted, request_id: request.id)
      { success: true, request: request }
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

Create `app/services/requests/accept_service.rb`:

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

Create `app/services/requests/decline_service.rb`:

```ruby
module Requests
  class DeclineService
    def initialize(request:, provider:)
      @request = request
      @provider = provider
    end

    def call
      return error("Not your request") unless @request.provider_id == @provider.id

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

Create `app/services/requests/start_service.rb`:

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

Create `app/services/requests/fulfill_service.rb`:

```ruby
module Requests
  class FulfillService
    def initialize(request:, provider:)
      @request = request
      @provider = provider
    end

    def call
      return error("Not your request") unless @request.provider_id == @provider.id

      @request.fulfill!

      if @request.payment&.status == "held"
        PaymentGateway.charge(@request.payment)
      end

      NotificationService.notify(@request.client, :request_fulfilled, request_id: @request.id)
      NotificationService.notify(@request.provider, :request_fulfilled, request_id: @request.id)
      { success: true, request: @request }
    rescue AASM::InvalidTransition
      error("Cannot fulfill request in #{@request.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
```

Create `app/services/requests/cancel_service.rb`:

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

Create `app/services/requests/reject_service.rb`:

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

- [ ] **Step 9: Update NotificationService**

In `affordance_request/app/services/notification_service.rb`:
- Change `OrderMailer` → `RequestMailer`

- [ ] **Step 10: Update PaymentGateway**

In `affordance_request/app/services/payment_gateway.rb`:
- Change `@payment.order.client` → `@payment.request.client`

- [ ] **Step 11: Update mailer**

Rename `app/mailers/order_mailer.rb` → `app/mailers/request_mailer.rb`. Replace content with request-specific naming:

```ruby
class RequestMailer < ApplicationMailer
  def request_created(recipient, payload)
    @request_id = payload[:request_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "New request ##{@request_id}")
  end

  def request_created_accepted(recipient, payload)
    @request_id = payload[:request_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "Request ##{@request_id} created and accepted")
  end

  def request_accepted(recipient, payload)
    @request_id = payload[:request_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "Request ##{@request_id} accepted")
  end

  def request_declined(recipient, payload)
    @request_id = payload[:request_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "Request ##{@request_id} declined")
  end

  def request_started(recipient, payload)
    @request_id = payload[:request_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "Request ##{@request_id} started")
  end

  def request_fulfilled(recipient, payload)
    @request_id = payload[:request_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "Request ##{@request_id} fulfilled")
  end

  def request_canceled(recipient, payload)
    @request_id = payload[:request_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "Request ##{@request_id} canceled")
  end

  def request_rejected(recipient, payload)
    @request_id = payload[:request_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "Request ##{@request_id} rejected")
  end

  def review_reminder(recipient, payload)
    @request_id = payload[:request_id]
    @recipient = recipient
    mail(to: recipient.email, subject: "Please review request ##{@request_id}")
  end
end
```

Rename mailer view directory: `app/views/order_mailer/` → `app/views/request_mailer/`. Update all view file content from "order" to "request".

- [ ] **Step 12: Update API controllers**

Delete `app/controllers/api/orders_controller.rb`. Create `app/controllers/api/requests_controller.rb`:

```ruby
module Api
  class RequestsController < BaseController
    before_action :find_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject]

    def index
      requests = if @current_client
        @current_client.requests
      else
        @current_provider.requests
      end

      requests = requests.by_state(params[:state])
                         .scheduled_between(params[:from], params[:to])
                         .sorted
                         .page(params[:page])

      render json: requests.map { |r| request_json(r) }
    end

    def show
      render json: request_json(@request, detailed: true)
    end

    def create
      client = current_client!
      return unless client

      result = Requests::CreateService.new(
        client: client,
        provider: Provider.find(params[:provider_id]),
        params: request_params
      ).call

      if result[:success]
        render json: request_json(result[:request]), status: :created
      else
        render_unprocessable(result[:errors]&.full_messages || [result[:error]])
      end
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Provider not found" }, status: :not_found
    end

    def create_direct
      provider = current_provider!
      return unless provider

      result = Requests::CreateAcceptedService.new(
        provider: provider,
        client: Client.find(params[:client_id]),
        params: request_params
      ).call

      if result[:success]
        render json: request_json(result[:request]), status: :created
      else
        render_unprocessable(result[:errors]&.full_messages || [result[:error]])
      end
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Client not found" }, status: :not_found
    end

    def accept
      provider = current_provider!
      return unless provider

      result = Requests::AcceptService.new(request: @request, provider: provider).call
      render_service_result(result)
    end

    def decline
      provider = current_provider!
      return unless provider

      result = Requests::DeclineService.new(request: @request, provider: provider).call
      render_service_result(result)
    end

    def start
      provider = current_provider!
      return unless provider

      result = Requests::StartService.new(request: @request, provider: provider).call
      render_service_result(result)
    end

    def fulfill
      provider = current_provider!
      return unless provider

      result = Requests::FulfillService.new(request: @request, provider: provider).call
      render_service_result(result)
    end

    def cancel
      client = current_client!
      return unless client

      result = Requests::CancelService.new(
        request: @request, client: client, reason: params[:reason]
      ).call
      render_service_result(result)
    end

    def reject
      provider = current_provider!
      return unless provider

      result = Requests::RejectService.new(
        request: @request, provider: provider, reason: params[:reason]
      ).call
      render_service_result(result)
    end

    private

    def find_request
      @request = Request.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_not_found
    end

    def request_params
      params.require(:request).permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
    end

    def render_service_result(result)
      if result[:success]
        render json: request_json(result[:request])
      else
        render json: { error: result[:error] }, status: :unprocessable_entity
      end
    end

    def request_json(request, detailed: false)
      json = {
        id: request.id,
        client_id: request.client_id,
        provider_id: request.provider_id,
        state: request.state,
        scheduled_at: request.scheduled_at,
        duration_minutes: request.duration_minutes,
        location: request.location,
        amount_cents: request.amount_cents,
        currency: request.currency,
        created_at: request.created_at
      }

      if detailed
        json[:notes] = request.notes
        json[:cancel_reason] = request.cancel_reason
        json[:reject_reason] = request.reject_reason
        json[:started_at] = request.started_at
        json[:completed_at] = request.completed_at
        json[:payment] = request.payment&.then { |p|
          { id: p.id, status: p.status, amount_cents: p.amount_cents, fee_cents: p.fee_cents }
        }
      end

      json
    end
  end
end
```

Update `app/controllers/api/reviews_controller.rb` — change all `order` → `request`, `Order` → `Request`, `order_id` → `request_id`:

```ruby
module Api
  class ReviewsController < BaseController
    before_action :find_request

    def index
      reviews = @request.reviews
      render json: reviews.map { |r| review_json(r) }
    end

    def create
      review = @request.reviews.new(
        author: current_user,
        rating: params[:rating],
        body: params[:body]
      )

      if review.save
        update_provider_rating if current_user.is_a?(Client)
        render json: review_json(review), status: :created
      else
        render_unprocessable(review.errors.full_messages)
      end
    end

    private

    def find_request
      @request = Request.find(params[:request_id])
    rescue ActiveRecord::RecordNotFound
      render_not_found
    end

    def review_json(review)
      {
        id: review.id,
        request_id: review.request_id,
        author_type: review.author_type,
        author_id: review.author_id,
        rating: review.rating,
        body: review.body,
        created_at: review.created_at
      }
    end

    def update_provider_rating
      provider = @request.provider
      avg = provider.reviews.average(:rating)
      provider.update!(rating: avg) if avg
    end
  end
end
```

Update `app/controllers/api/payments_controller.rb` — change `order` joins to `request`:

```ruby
module Api
  class PaymentsController < BaseController
    def index
      payments = if @current_client
        Payment.joins(:request).where(requests: { client_id: @current_client.id })
      else
        Payment.joins(:request).where(requests: { provider_id: @current_provider.id })
      end

      payments = payments.by_status(params[:status]).order(created_at: :desc)
      render json: payments.map { |p| payment_json(p) }
    end

    def show
      payment = Payment.find(params[:id])
      request = payment.request
      unless request.client_id == @current_client&.id || request.provider_id == @current_provider&.id
        return render_forbidden
      end
      render json: payment_json(payment)
    rescue ActiveRecord::RecordNotFound
      render_not_found
    end

    private

    def payment_json(payment)
      {
        id: payment.id,
        request_id: payment.request_id,
        amount_cents: payment.amount_cents,
        currency: payment.currency,
        fee_cents: payment.fee_cents,
        status: payment.status,
        held_at: payment.held_at,
        charged_at: payment.charged_at,
        refunded_at: payment.refunded_at,
        created_at: payment.created_at
      }
    end
  end
end
```

- [ ] **Step 13: Update routes**

Replace `config/routes.rb`:

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
      collection do
        post :direct, action: :create_direct
      end

      member do
        patch :accept
        patch :decline
        patch :start
        patch :fulfill
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
    resources :clients, only: [:index, :show]
    resources :providers, only: [:index, :show]
    resources :payments, only: [:index, :show]
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
```

- [ ] **Step 14: Update admin controllers**

Rename and update admin orders controller → requests:

```ruby
# app/controllers/admin/requests_controller.rb
module Admin
  class RequestsController < BaseController
    def index
      @requests = Request.includes(:client, :provider)
                         .by_state(params[:state])
                         .by_client(params[:client_id])
                         .by_provider(params[:provider_id])
                         .scheduled_between(params[:from], params[:to])
                         .sorted
      @requests = paginate(@requests)
    end

    def show
      @request = Request.includes(:payment, :reviews, :client, :provider).find(params[:id])
    end
  end
end
```

Update `admin/dashboard_controller.rb` — change `Order` → `Request`.

Update `admin/clients_controller.rb` — change `@orders` → `@requests`, `client.orders` → `client.requests`.

Update `admin/providers_controller.rb` — change `@orders` → `@requests`, `provider.orders` → `provider.requests`.

Update `admin/payments_controller.rb` — change `order:` includes to `request:`.

- [ ] **Step 15: Update admin views**

Rename `app/views/admin/orders/` → `app/views/admin/requests/`.

Update all admin views:
- Replace "order" with "request", "Order" with "Request"
- Replace state badge classes to include legacy states: `created`, `created_accepted`, `accepted`, `fulfilled`, `declined`, `missed`
- Update dashboard to show "Requests" instead of "Orders"
- Update nav link from "Orders" → "Requests", paths from `/admin/orders` → `/admin/requests`
- Update layout nav link

- [ ] **Step 16: Update jobs**

In `app/jobs/payment_hold_job.rb`:
- Change `Order.where(state:` to use request states (`%w[created created_accepted accepted]`)
- Change `Order` → `Request`

```ruby
class PaymentHoldJob < ApplicationJob
  queue_as :default

  def perform
    requests = Request.where(state: %w[created created_accepted accepted])
                      .where("scheduled_at BETWEEN ? AND ?", Time.current, 1.day.from_now)
                      .includes(:payment, client: :cards)

    requests.find_each do |request|
      next unless request.payment&.status == "pending"

      result = PaymentGateway.hold(request.payment)
      Rails.logger.info "[PaymentHoldJob] request_id=#{request.id} success=#{result[:success]} error=#{result[:error]}"
    end
  end
end
```

In `app/jobs/review_reminder_job.rb`:
- Change `Order` → `Request`, state `"completed"` → `"fulfilled"`, `completed_at` stays as column name

```ruby
class ReviewReminderJob < ApplicationJob
  queue_as :default

  def perform
    requests = Request.where(state: "fulfilled")
                      .where("completed_at < ?", 24.hours.ago)
                      .where("completed_at > ?", 48.hours.ago)
                      .includes(:reviews, :client, :provider)

    requests.find_each do |request|
      remind_client(request) unless request.reviews.exists?(author: request.client)
      remind_provider(request) unless request.reviews.exists?(author: request.provider)
    end
  end

  private

  def remind_client(request)
    NotificationService.notify(request.client, :review_reminder, request_id: request.id)
  end

  def remind_provider(request)
    NotificationService.notify(request.provider, :review_reminder, request_id: request.id)
  end
end
```

- [ ] **Step 17: Update all factories**

Rename `spec/factories/orders.rb` → `spec/factories/requests.rb`:

```ruby
FactoryBot.define do
  factory :request do
    client
    provider
    scheduled_at { 3.days.from_now }
    duration_minutes { 120 }
    location { "123 Main St" }
    notes { "Please bring supplies" }
    amount_cents { 350_000 }
    currency { "RUB" }

    trait :created_accepted do
      state { "created_accepted" }
    end

    trait :accepted do
      state { "accepted" }
    end

    trait :started do
      state { "started" }
      started_at { Time.current }
    end

    trait :fulfilled do
      state { "fulfilled" }
      started_at { 2.hours.ago }
      completed_at { Time.current }
    end

    trait :declined do
      state { "declined" }
    end

    trait :missed do
      state { "missed" }
    end

    trait :canceled do
      state { "canceled" }
      cancel_reason { "Schedule changed" }
    end

    trait :rejected do
      state { "rejected" }
      reject_reason { "Cannot make it" }
    end

    trait :with_payment do
      after(:create) do |request|
        create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
      end
    end

    trait :with_card do
      after(:create) do |request|
        create(:card, client: request.client, default: true)
      end
    end

    trait :scheduled_tomorrow do
      scheduled_at { 1.day.from_now }
    end
  end
end
```

Update `spec/factories/payments.rb` — change `order` → `request`.

Update `spec/factories/reviews.rb` — change `order` → `request`, trait `:completed` → `:fulfilled`.

- [ ] **Step 18: Update all specs**

This is a comprehensive find-and-replace across all spec files:

- Rename `spec/models/order_spec.rb` → `spec/models/request_spec.rb`
- Rename `spec/services/orders/` → `spec/services/requests/`
- Rename `spec/requests/api/orders_spec.rb` → `spec/requests/api/requests_spec.rb`
- Rename `spec/requests/admin/orders_spec.rb` → `spec/requests/admin/requests_spec.rb`
- Rename `spec/mailers/order_mailer_spec.rb` → `spec/mailers/request_mailer_spec.rb`

In every spec file:
- Replace `Order` → `Request`, `order` → `request`, `orders` → `requests`
- Replace `/api/orders` → `/api/requests`, `/admin/orders` → `/admin/requests`
- Replace state names: `:confirmed` → `:accepted`, `:in_progress` → `:started`, `:completed` → `:fulfilled`
- Replace event names: `confirm` → `accept`, `complete` → `fulfill`
- Replace `order_id` → `request_id` in payloads
- Replace `OrderMailer` → `RequestMailer`
- Replace `"order_confirmed"` → `"request_accepted"`, etc.

Add specs for Request-specific features:
- `spec/services/requests/create_accepted_service_spec.rb`
- `spec/services/requests/decline_service_spec.rb`
- Additional state transition specs for `created_accepted`, `declined`, `missed`
- `POST /api/requests/direct` endpoint spec

Create `spec/services/requests/create_accepted_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Requests::CreateAcceptedService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:params) do
    {
      scheduled_at: 3.days.from_now,
      duration_minutes: 120,
      location: "123 Main St",
      notes: "Direct booking",
      amount_cents: 350_000,
      currency: "RUB"
    }
  end

  describe "#call" do
    it "creates a request in created_accepted state" do
      result = described_class.new(provider: provider, client: client, params: params).call
      expect(result[:success]).to be true
      expect(result[:request].state).to eq("created_accepted")
    end

    it "creates a pending payment" do
      result = described_class.new(provider: provider, client: client, params: params).call
      payment = result[:request].payment
      expect(payment).to be_present
      expect(payment.status).to eq("pending")
    end

    it "notifies client" do
      described_class.new(provider: provider, client: client, params: params).call
      log = read_notification_log
      expect(log).to include("event=request_created_accepted")
    end
  end
end
```

Create `spec/services/requests/decline_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Requests::DeclineService do
  let(:request) { create(:request) }
  let(:provider) { request.provider }

  describe "#call" do
    it "declines a created request" do
      result = described_class.new(request: request, provider: provider).call
      expect(result[:success]).to be true
      expect(request.reload.state).to eq("declined")
    end

    it "notifies client" do
      described_class.new(request: request, provider: provider).call
      log = read_notification_log
      expect(log).to include("event=request_declined")
    end

    it "fails if not the request's provider" do
      other_provider = create(:provider)
      result = described_class.new(request: request, provider: other_provider).call
      expect(result[:success]).to be false
    end

    it "fails if request is accepted" do
      request = create(:request, :accepted)
      result = described_class.new(request: request, provider: request.provider).call
      expect(result[:success]).to be false
    end
  end
end
```

- [ ] **Step 19: Remove leftover Order files**

```bash
cd /home/cutalion/code/affordance_test/affordance_request
rm -f app/models/order.rb
rm -rf app/services/orders/
rm -f app/controllers/api/orders_controller.rb
rm -f app/controllers/admin/orders_controller.rb
rm -f app/mailers/order_mailer.rb
rm -rf app/views/order_mailer/
rm -rf app/views/admin/orders/
rm -f spec/models/order_spec.rb
rm -rf spec/services/orders/
rm -f spec/requests/api/orders_spec.rb
rm -f spec/requests/admin/orders_spec.rb
rm -f spec/mailers/order_mailer_spec.rb
rm -f spec/factories/orders.rb
```

- [ ] **Step 20: Delete old database files and re-migrate**

```bash
cd /home/cutalion/code/affordance_test/affordance_request
rm -f db/*.sqlite3
bin/rails db:create db:migrate
```

- [ ] **Step 21: Run all Request app specs**

```bash
cd /home/cutalion/code/affordance_test/affordance_request
bundle exec rspec
```

Fix any failures.

- [ ] **Step 22: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add affordance_request
git commit -m "feat: create Request app - adapted from Order app with legacy invitation-era states"
```

---

### Task 13: Final Verification — Both Apps Green

- [ ] **Step 1: Run Order app specs**

```bash
cd /home/cutalion/code/affordance_test/affordance_order
bundle exec rspec
```

Expected: All pass

- [ ] **Step 2: Run Request app specs**

```bash
cd /home/cutalion/code/affordance_test/affordance_request
bundle exec rspec
```

Expected: All pass

- [ ] **Step 3: Verify both apps start**

```bash
cd /home/cutalion/code/affordance_test/affordance_order
bin/rails runner "puts 'Order app OK: #{Order.count} orders, #{Client.count} clients'"

cd /home/cutalion/code/affordance_test/affordance_request
bin/rails runner "puts 'Request app OK: #{Request.count} requests, #{Client.count} clients'"
```

- [ ] **Step 4: Final commit**

```bash
cd /home/cutalion/code/affordance_test
git add -A
git commit -m "chore: final verification - both apps passing all specs"
```
