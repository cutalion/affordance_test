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
