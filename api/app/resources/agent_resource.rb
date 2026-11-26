# The listing agent on the property page: who to call or email.
class AgentResource
  include Alba::Resource

  transform_keys :lower_camel

  attributes :id, :name, :agency, :phone, :email
end
