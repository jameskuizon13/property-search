# The listing agent shown on a property page, so a buyer can call or email
# about a listing. Contact details only: no logins, no enquiry records.
class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents do |t|
      t.string :name, null: false
      t.string :agency, null: false
      t.string :phone, null: false
      t.string :email, null: false
      t.timestamps
    end

    # A property keeps its listing if its agent is removed; it just shows no agent.
    add_reference :properties, :agent, foreign_key: { on_delete: :nullify }
  end
end
