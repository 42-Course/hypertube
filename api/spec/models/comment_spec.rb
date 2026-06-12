require "rails_helper"

RSpec.describe Comment, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:content) }
    it { is_expected.to validate_length_of(:content).is_at_most(1000) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:movie) }
  end
end
