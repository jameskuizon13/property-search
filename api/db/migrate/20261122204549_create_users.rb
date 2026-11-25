class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      # Stored trimmed + lowercased by `normalizes :email` on User, so a plain
      # unique index is enough to make email case-insensitive.
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :name, null: false

      t.timestamps
    end

    add_index :users, :email, unique: true
  end
end
