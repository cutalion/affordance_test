# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_09_084335) do
  create_table "announcements", force: :cascade do |t|
    t.integer "budget_cents"
    t.integer "client_id", null: false
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.string "currency", default: "RUB", null: false
    t.text "description"
    t.integer "duration_minutes"
    t.string "location"
    t.datetime "published_at"
    t.datetime "scheduled_at"
    t.string "state", default: "draft", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_announcements_on_client_id"
    t.index ["state"], name: "index_announcements_on_state"
  end

  create_table "cards", force: :cascade do |t|
    t.string "brand", null: false
    t.integer "client_id", null: false
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.integer "exp_month", null: false
    t.integer "exp_year", null: false
    t.string "last_four", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_cards_on_client_id"
  end

  create_table "clients", force: :cascade do |t|
    t.string "api_token", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.text "notification_preferences", default: "{\"push\":true,\"sms\":true,\"email\":true}", null: false
    t.string "phone"
    t.datetime "updated_at", null: false
    t.index ["api_token"], name: "index_clients_on_api_token", unique: true
    t.index ["email"], name: "index_clients_on_email", unique: true
  end

  create_table "payments", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "card_id"
    t.datetime "charged_at"
    t.datetime "created_at", null: false
    t.string "currency", default: "RUB", null: false
    t.integer "fee_cents", default: 0, null: false
    t.datetime "held_at"
    t.datetime "refunded_at"
    t.integer "request_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_payments_on_card_id"
    t.index ["request_id"], name: "index_payments_on_request_id"
    t.index ["status"], name: "index_payments_on_status"
  end

  create_table "providers", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "api_token", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.text "notification_preferences", default: "{\"push\":true,\"sms\":true,\"email\":true}", null: false
    t.string "phone"
    t.decimal "rating", precision: 3, scale: 2, default: "0.0"
    t.string "specialization"
    t.datetime "updated_at", null: false
    t.index ["api_token"], name: "index_providers_on_api_token", unique: true
    t.index ["email"], name: "index_providers_on_email", unique: true
  end

  create_table "requests", force: :cascade do |t|
    t.datetime "accepted_at"
    t.integer "amount_cents", null: false
    t.integer "announcement_id"
    t.text "cancel_reason"
    t.integer "client_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "currency", default: "RUB", null: false
    t.text "decline_reason"
    t.integer "duration_minutes", null: false
    t.datetime "expired_at"
    t.string "location"
    t.text "notes"
    t.integer "proposed_amount_cents"
    t.integer "provider_id", null: false
    t.string "recurring_group_id"
    t.integer "recurring_index"
    t.text "reject_reason"
    t.text "response_message"
    t.datetime "scheduled_at", null: false
    t.datetime "started_at"
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.text "withdraw_reason"
    t.datetime "withdrawn_at"
    t.index ["announcement_id"], name: "index_requests_on_announcement_id"
    t.index ["client_id"], name: "index_requests_on_client_id"
    t.index ["provider_id"], name: "index_requests_on_provider_id"
    t.index ["recurring_group_id"], name: "index_requests_on_recurring_group_id"
    t.index ["scheduled_at"], name: "index_requests_on_scheduled_at"
    t.index ["state"], name: "index_requests_on_state"
  end

  create_table "reviews", force: :cascade do |t|
    t.integer "author_id", null: false
    t.string "author_type", null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "rating", null: false
    t.integer "request_id", null: false
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_reviews_on_author_type_and_author_id"
    t.index ["request_id", "author_type", "author_id"], name: "index_reviews_on_request_id_and_author_type_and_author_id", unique: true
    t.index ["request_id"], name: "index_reviews_on_request_id"
  end

  add_foreign_key "announcements", "clients"
  add_foreign_key "cards", "clients"
  add_foreign_key "payments", "cards"
  add_foreign_key "payments", "requests"
  add_foreign_key "requests", "announcements"
  add_foreign_key "requests", "clients"
  add_foreign_key "requests", "providers"
  add_foreign_key "reviews", "requests"
end
