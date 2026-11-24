class AddRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    # String-backed enum (see User). Sign-up never sets it; only the seed and,
    # later, an admin can. The CHECK keeps bad values out even outside Rails.
    add_column :users, :role, :string, null: false, default: "user"
    add_check_constraint :users, "role IN ('user', 'admin')", name: "users_role_check"
  end
end
