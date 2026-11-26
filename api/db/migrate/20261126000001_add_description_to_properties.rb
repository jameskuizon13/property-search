# The listing's write-up, shown on the property page. Nullable: an admin can
# create a listing before writing one. Search never reads it, so it adds
# nothing to the search indexes or the list payload.
class AddDescriptionToProperties < ActiveRecord::Migration[8.1]
  def change
    add_column :properties, :description, :text
  end
end
