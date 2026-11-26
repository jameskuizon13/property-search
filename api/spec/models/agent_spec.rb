require "rails_helper"

RSpec.describe Agent do
  it "is valid with a name, agency, phone and email" do
    expect(build(:agent)).to be_valid
  end

  it "normalises the email to lowercase" do
    expect(create(:agent, email: " Mia.Chen@Example.com ").email).to eq("mia.chen@example.com")
  end

  it "rejects a phone with letters and an email without a domain" do
    agent = build(:agent, phone: "call me", email: "mia")
    expect(agent).not_to be_valid
    expect(agent.errors.attribute_names).to contain_exactly(:phone, :email)
  end

  it "leaves its listings in place, without an agent, when deleted" do
    agent = create(:agent)
    property = create(:property, agent:)
    agent.delete

    expect(property.reload.agent_id).to be_nil
  end

  it "rejects an email that would change a mailto: link" do
    %w[bob?bcc=evil@example.com bob#x@example.com a%3fbcc%3dx@example.com a%2cb@example.com mia@example].each do |email|
      expect(build(:agent, email:)).not_to be_valid, "expected #{email} to be rejected"
    end
  end
end
