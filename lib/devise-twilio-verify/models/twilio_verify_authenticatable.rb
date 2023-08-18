require 'digest'
require 'devise-twilio-verify/hooks/twilio_verify_authenticatable'
module Devise
  module Models
    module TwilioVerifyAuthenticatable
      extend ActiveSupport::Concern

      included do
        unless Devise.twilio_verify_resource_phone_attribute == :mobile_phone
          alias_attribute :mobile_phone, Devise.twilio_verify_resource_phone_attribute
        end
      end

      def with_twilio_verify_authentication?(_request)
        # TODO: This assumes TOTP, need to consider SMS based approach too
        self.twilio_verify_enabled? && self.twilio_totp_factor_sid.present?
      end

      def twilio_identifier
        Digest::SHA256.hexdigest(app_identifier)
      end

      def mobile_phone_valid?
        Phonelib.valid?(self.mobile_phone)
      end

      private

      def app_identifier
        [Rails.env, self.id].join('-')
      end

      class_methods do
        def find_by_mobile_phone(phone_number)
          where(Devise.twilio_verify_resource_phone_attribute => phone_number).first
        end

        Devise::Models.config(
          self,
          :twilio_verify_remember_device, :twilio_verify_enable_qr_code,
          :twilio_verify_resource_phone_attribute
        )
      end
    end
  end
end

