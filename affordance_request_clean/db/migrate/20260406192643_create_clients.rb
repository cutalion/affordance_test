class CreateClients < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :phone
      t.string :api_token, null: false
      t.text :notification_preferences, null: false, default: '{"push":true,"sms":true,"email":true}'

      t.timestamps
    end

    add_index :clients, :email, unique: true
    add_index :clients, :api_token, unique: true
  end
end
