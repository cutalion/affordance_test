class CreateProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :providers do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :phone
      t.string :api_token, null: false
      t.decimal :rating, precision: 3, scale: 2, default: 0.0
      t.string :specialization
      t.boolean :active, null: false, default: true
      t.text :notification_preferences, null: false, default: '{"push":true,"sms":true,"email":true}'

      t.timestamps
    end

    add_index :providers, :email, unique: true
    add_index :providers, :api_token, unique: true
  end
end
