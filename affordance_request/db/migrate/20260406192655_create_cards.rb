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
