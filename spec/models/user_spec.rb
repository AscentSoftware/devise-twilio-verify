# frozen_string_literal: true

RSpec.describe User, type: :model do
  describe "with a user with a mobile phone" do
    let!(:user) { create(:twilio_verify_user) }

    describe "User.find_by_mobile_phone" do
      it "should find the user" do
        expect(User.first).not_to be nil
        expect(User.find_by_mobile_phone(user.mobile_phone)).to eq(user)
      end

      it "shouldn't find the user with the wrong mobile phone" do
        expect(User.find_by_mobile_phone('21')).to be nil
      end
    end

    describe "User#with_twilio_verify_authentication?" do
      it "should be false when twilio verify isn't enabled" do
        user.twilio_verify_enabled = false
        request = double("request")
        expect(user.with_twilio_verify_authentication?(request)).to be false
      end

      it "should be true when twilio verify is enabled" do
        user.twilio_verify_enabled = true
        request = double("request")
        expect(user.with_twilio_verify_authentication?(request)).to be true
      end
    end

    context "when Devise.twilio_verify_resource_phone_attribute config is set to some other attribute" do
      let(:user_with_telephone_attributes) { attributes_for(:user_with_telephone) }
      let(:user_with_telephone) { TelephoneUser.create(user_with_telephone_attributes) }

      before do
        Devise.setup { |config| config.twilio_verify_resource_phone_attribute = :telephone }
        class TelephoneUser < ActiveRecord::Base
          self.table_name = :users

          devise :twilio_verify_authenticatable, :database_authenticatable
        end
      end

      after do
        Devise.setup { |config| config.twilio_verify_resource_phone_attribute = :mobile_phone }
      end

      it "adds an alias called User#mobile_phone for User#telephone" do
        expect(user_with_telephone_attributes[:mobile_phone]).to be_nil
        expect(user_with_telephone.mobile_phone).not_to be_nil
      end

      it "should find the user through telephone only" do
        expect(
          TelephoneUser.find_by_mobile_phone(user_with_telephone.telephone)
        ).to eq(user_with_telephone)
        expect(
          TelephoneUser.where(mobile_phone: user_with_telephone.telephone).first
        ).to eq(user_with_telephone)
        expect(
          TelephoneUser.where("mobile_phone = ?", user_with_telephone.telephone).first
        ).to be_nil
      end

      it "TelephoneUser#mobile_phone returns TelephoneUser#telephone" do
        expect(user_with_telephone.mobile_phone).to eq(user_with_telephone.telephone)
      end

      it "TelephoneUser#mobile_phone= sets TelephoneUser#telephone" do
        user_with_telephone.update(mobile_phone: '123')
        user_with_telephone.reload
        expect(user_with_telephone.mobile_phone).to eq(user_with_telephone.telephone)
        expect(user_with_telephone.telephone).to eq('123')
      end
    end

  end

  describe "with a user without a mobile phone" do
    let!(:user) { create(:user, mobile_phone: nil) }

    describe "user#with_twilio_verify_authentication?" do
      it "should be false regardless of twilio_verify_enabled field" do
        request = double("request")
        expect(user.with_twilio_verify_authentication?(request)).to be false
        user.twilio_verify_enabled = true
        expect(user.with_twilio_verify_authentication?(request)).to be false
      end
    end
  end

  describe "#twilio_verify_id" do
    let(:user) { create(:user) }

    it "returns a combination of env and user id" do
      allow(Rails).to receive(:env) { 'env' }
      expect(user.twilio_verify_id).to eq("env-#{user.id}")
      allow(Rails).to receive(:env).and_call_original
    end
  end
end
