require "rails_helper"

RSpec.describe "Log parameter filtering" do
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  it "never logs passwords, emails, tokens or cursors" do
    filtered = filter.filter(
      "password" => "secret", "password_confirmation" => "secret", "email" => "a@b.c",
      "token" => "jwt", "auth_token" => "jwt", "cursor" => "abc", "name" => "Alice"
    )

    expect(filtered.except("name").values).to all(eq("[FILTERED]"))
    expect(filtered["name"]).to eq("Alice")
  end
end
