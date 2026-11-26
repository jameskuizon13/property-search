FactoryBot.define do
  factory :property do
    sequence(:street_address) { |n| "#{n} Smith St" }
    suburb { "Fitzroy" }
    state { "VIC" }
    postcode { "3065" }
    latitude { -37.798 }
    longitude { 144.978 }
    price_cents { 85_000_000 }
    price_display { "$850,000" }
    bedrooms { 3 }
    bathrooms { 2 }
    car_spaces { 1 }
    land_size_sqm { 320 }
    property_type { "house" }
    status { "for_sale" }
    listed_at { Time.current }

    trait :price_withheld do
      price_cents { nil }
      price_display { "Contact agent" }
    end
  end

  factory :property_event do
    property
    kind { "price_changed" }
    from_value { "85000000" }
    to_value { "82000000" }
  end
end

FactoryBot.define do
  factory :agent do
    sequence(:name) { |n| "Agent #{n}" }
    agency { "Laneway Property Co" }
    phone { "0491 570 156" }
    sequence(:email) { |n| "agent#{n}@example.com" }
  end

  factory :inspection do
    property
    starts_at { 2.days.from_now.change(hour: 10) }
    ends_at { starts_at + 30.minutes }
  end

  factory :property_photo do
    property
    sequence(:position) { |n| n }
    url { "/images/properties/kitchen-01.webp" }
    caption { "Kitchen" }
  end
end
