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
