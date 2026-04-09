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
