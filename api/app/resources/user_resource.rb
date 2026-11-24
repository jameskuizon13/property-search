# Allow-lists the fields a client may see; password_digest is never serialised.
class UserResource
  include Alba::Resource

  transform_keys :lower_camel

  attributes :id, :email, :name
end
