class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :order, null: false, foreign_key: true
      t.references :card, null: true, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "RUB"
      t.integer :fee_cents, null: false, default: 0
      t.string :status, null: false, default: "pending"
      t.datetime :held_at
      t.datetime :charged_at
      t.datetime :refunded_at

      t.timestamps
    end

    add_index :payments, :status
  end
end
