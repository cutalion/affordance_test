class AddAnnouncementToRequests < ActiveRecord::Migration[8.1]
  def change
    add_reference :requests, :announcement, null: true, foreign_key: true
    add_column :requests, :response_message, :text
    add_column :requests, :proposed_amount_cents, :integer
  end
end
