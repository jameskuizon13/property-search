# Allow-lists the fields a client may see; password_digest is never serialised.
# role tells the UI whether to show the admin link (the server still checks).
class UserResource
  include Alba::Resource

  transform_keys :lower_camel

  attributes :id, :email, :name, :role
end
