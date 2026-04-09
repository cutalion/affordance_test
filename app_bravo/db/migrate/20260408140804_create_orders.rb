class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :request, null: true, foreign_key: true
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
