require "rails_helper"

RSpec.describe PropertyPhoto do
  it "keeps one photo per position in a gallery, and the gallery in order" do
    property = create(:property)
    second = create(:property_photo, property:, position: 2)
    first = create(:property_photo, property:, position: 1)

    expect(build(:property_photo, property:, position: 1)).not_to be_valid
    expect(property.photos).to eq([ first, second ])
  end

  it "needs a caption, for screen readers" do
    expect(build(:property_photo, caption: "")).not_to be_valid
  end

  it "only points at the web app's own photos" do
    [ "javascript:alert(1)", "https://evil.example/x.webp", "/images/../secret.webp" ].each do |url|
      expect(build(:property_photo, url:)).not_to be_valid, "expected #{url} to be rejected"
    end
  end
end
