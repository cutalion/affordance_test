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

ActiveRecord::Schema[8.1].define(version: 2026_04_08_140803) do
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
    t.integer "client_id", null: false
    t.datetime "created_at", null: false
    t.text "decline_reason"
    t.integer "duration_minutes", null: false
    t.datetime "expired_at"
    t.string "location"
    t.text "notes"
    t.integer "provider_id", null: false
    t.datetime "scheduled_at", null: false
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_requests_on_client_id"
    t.index ["provider_id"], name: "index_requests_on_provider_id"
    t.index ["scheduled_at"], name: "index_requests_on_scheduled_at"
    t.index ["state"], name: "index_requests_on_state"
  end

  add_foreign_key "cards", "clients"
  add_foreign_key "requests", "clients"
  add_foreign_key "requests", "providers"
end
