# Open-home times. The property page lists the upcoming ones.
class CreateInspections < ActiveRecord::Migration[8.1]
  def change
    create_table :inspections do |t|
      t.references :property, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.timestamps
    end

    add_check_constraint :inspections, "ends_at > starts_at", name: "inspections_ends_after_start"
    # "This property's upcoming inspections, soonest first."
    add_index :inspections, %i[property_id starts_at]
  end
end
