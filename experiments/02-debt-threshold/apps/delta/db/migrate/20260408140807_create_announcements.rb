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
