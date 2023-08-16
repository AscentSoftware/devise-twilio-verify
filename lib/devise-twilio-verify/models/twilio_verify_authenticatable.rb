require 'devise-twilio-verify/hooks/twilio_verify_authenticatable'
module Devise
  module Models
    module TwilioVerifyAuthenticatable
      extend ActiveSupport::Concern

      def with_twilio_verify_authentication?(_request)
        self.twilio_verify_enabled? && self.mobile_phone.present?
      end

      def twilio_verify_id
        [Rails.env, self.id].join('-')
      end

      included do
        unless Devise.twilio_verify_resource_phone_attribute == :mobile_phone
          alias_attribute :mobile_phone, Devise.twilio_verify_resource_phone_attribute
        end
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

