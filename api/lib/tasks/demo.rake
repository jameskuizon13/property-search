# Tasks for seeing live updates without an admin screen. Every change goes
# through update!, so it writes a property_events row and reaches watchers
# exactly like an admin edit would. In Docker, prefix with
# `docker compose exec api`.
namespace :demo do
  module DemoTasks
    STEP_CENTS = 500_000 # $5,000: seed prices are rounded to it
    MIN_PRICE_CENTS = 5_000_000 # $50,000
    MIN_DOLLARS = 1_000 # a typo guard: price=1 is almost certainly a mistake
    STATUS_STEPS = { "for_sale" => "under_offer", "under_offer" => "sold", "sold" => "for_sale", "withdrawn" => "for_sale" }.freeze

    module_function

    # A method, not a constant: rake loads this file before the app's models.
    def change_usage
      <<~USAGE
        Usage: bin/rails "demo:change_property[ID,price=DOLLARS]"
               bin/rails "demo:change_property[ID,price=withheld]"
               bin/rails "demo:change_property[ID,status=#{Property::STATUSES.join('|')}]"
        Find ids your demo user watches with: bin/rails demo:watched
      USAGE
    end

    def fail_with(message)
      warn message
      exit 1
    end

    # "price=820000" → { price_cents:, price_display: }; "status=sold" → { status: }.
    def parse_change(change)
      key, value = change.to_s.split("=", 2)
      case key
      when "price"
        return { price_cents: nil, price_display: "Contact agent" } if value == "withheld"

        dollars = Integer(value.to_s, 10, exception: false)
        max = Property::MAX_PRICE_CENTS / 100
        unless dollars && dollars.between?(MIN_DOLLARS, max)
          fail_with("Price must be whole dollars from #{MIN_DOLLARS} to #{max}, e.g. price=820000\n#{change_usage}")
        end
        price_attributes(dollars * 100)
      when "status"
        fail_with("Unknown status #{value.inspect}\n#{change_usage}") unless Property::STATUSES.include?(value)
        { status: value }
      else
        fail_with(change_usage)
      end
    end

    def price_attributes(cents) = { price_cents: cents, price_display: Property.format_price(cents) }

    # A price move of 2–10% (at least one $5,000 step, so something always
    # changes), or 1 in 4 times a status step. Withheld prices always step.
    def random_change(property, random)
      if property.price_cents.nil? || random.rand(4).zero?
        { status: STATUS_STEPS.fetch(property.status) }
      else
        steps = [ (property.price_cents * random.rand(0.02..0.10) / STEP_CENTS).round, 1 ].max
        steps = -steps if random.rand(2).zero? && property.price_cents - (steps * STEP_CENTS) >= MIN_PRICE_CENTS
        price_attributes(property.price_cents + (steps * STEP_CENTS))
      end
    end

    def describe(property)
      changes = property.saved_changes.slice("price_cents", "status").map do |attribute, (from, to)|
        if attribute == "price_cents"
          "#{from ? Property.format_price(from) : 'withheld'} → #{to ? Property.format_price(to) : 'withheld'}"
        else
          "#{from} → #{to}"
        end
      end
      "##{property.id} #{property.street_address}, #{property.suburb}: #{changes.join(', ')}"
    end

    def apply(property, attributes)
      property.update!(attributes)
      if property.saved_changes.slice("price_cents", "status").empty?
        puts "##{property.id}: already has those values, nothing to send"
      else
        watchers = property.watchlist_items.count
        puts "#{describe(property)} (#{watchers} #{'watcher'.pluralize(watchers)})"
      end
    end
  end

  desc "Change one property's price or status: demo:change_property[ID,price=820000|price=withheld|status=sold]"
  task :change_property, %i[id change] => :environment do |_task, args|
    DemoTasks.fail_with("Too many arguments: #{args.extras.inspect}\n#{DemoTasks.change_usage}") if args.extras.any?
    property = Property.find_by(id: Integer(args[:id].to_s, 10, exception: false))
    DemoTasks.fail_with("No property with id #{args[:id].inspect}\n#{DemoTasks.change_usage}") unless property

    DemoTasks.apply(property, DemoTasks.parse_change(args[:change]))
  rescue ActiveRecord::RecordInvalid => e
    DemoTasks.fail_with(e.message)
  end

  desc "Change COUNT (default 3) random watched properties"
  task simulate_changes: :environment do
    count = Integer(ENV.fetch("COUNT", "3"), 10, exception: false)
    DemoTasks.fail_with("COUNT must be a positive whole number") unless count&.positive?

    ids = WatchlistItem.distinct.pluck(:property_id).sample(count)
    next puts("No watched properties yet: sign in as demo@example.com and watch a few first.") if ids.empty?

    random = Random.new
    Property.where(id: ids).find_each do |property|
      DemoTasks.apply(property, DemoTasks.random_change(property, random))
    end
  end

  desc "List the properties a user watches (default demo@example.com)"
  task :watched, %i[email] => :environment do |_task, args|
    email = args[:email].presence || "demo@example.com"
    user = User.find_by(email: email.strip.downcase)
    DemoTasks.fail_with("No user #{email}") unless user

    items = user.watchlist_items.includes(:property).order(created_at: :desc)
    next puts("#{user.email} watches nothing yet.") if items.empty?

    items.each do |item|
      property = item.property
      puts "##{property.id}  #{property.street_address}, #{property.suburb} #{property.state}  #{property.price_display}  (#{property.status})"
    end
  end
end
