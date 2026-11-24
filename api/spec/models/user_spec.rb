require "rails_helper"

RSpec.describe User, type: :model do
  subject { build(:user) }

  it { is_expected.to validate_presence_of(:email) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to have_secure_password }

  it "defaults to the user role" do
    expect(described_class.new.role).to eq("user")
    expect(create(:user)).to be_user
  end

  it "has string-backed user and admin roles" do
    expect(described_class.roles).to eq("user" => "user", "admin" => "admin")
  end

  it "reports an unknown role as a validation error" do
    user = build(:user, role: "superuser")
    expect(user).not_to be_valid
    expect(user.errors[:role]).to be_present
  end

  it "accepts every role the model allows in the database" do
    rows = User::ROLES.map.with_index do |role, i|
      { email: "role#{i}@example.com", name: "R", password_digest: "x", role:, created_at: Time.current, updated_at: Time.current }
    end
    expect { User.insert_all!(rows) }.to change(User, :count).by(rows.size)
  end

  it "has a CHECK constraint on role" do
    user = create(:user)
    expect { user.update_columns(role: "superuser") }.to raise_error(ActiveRecord::StatementInvalid, /check/i)
  end

  it "stores email trimmed and lowercased" do
    user = create(:user, email: "  Alice@Example.COM ")
    expect(user.reload.email).to eq("alice@example.com")
  end

  it "treats email as case-insensitive for uniqueness" do
    create(:user, email: "alice@example.com")
    dup = build(:user, email: "ALICE@example.com")
    expect(dup).not_to be_valid
    expect(dup.errors[:email]).to include("has already been taken")
  end

  it "is backed by a unique index, not just the validation" do
    create(:user, email: "alice@example.com")
    dup = build(:user, email: "alice@example.com")
    expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "rejects a malformed email" do
    expect(build(:user, email: "not-an-email")).not_to be_valid
  end

  it "requires a password of 12 to 72 characters" do
    expect(build(:user, password: "a" * 11)).not_to be_valid
    expect(build(:user, password: "a" * 12)).to be_valid
    expect(build(:user, password: "a" * 72)).to be_valid
    expect(build(:user, password: "a" * 73)).not_to be_valid
  end

  it "finds users by email regardless of case in authenticate_by" do
    user = create(:user, email: "alice@example.com", password: "correct horse battery")
    expect(User.authenticate_by(email: " ALICE@example.com", password: "correct horse battery")).to eq(user)
  end
end
