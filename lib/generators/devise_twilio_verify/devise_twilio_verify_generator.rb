# frozen_string_literal: true

module DeviseTwilioVerify
  module Generators
    class DeviseTwilioVerifyGenerator < Rails::Generators::NamedBase
      namespace "devise_twilio_verify"

      desc "Add :twilio_verify_authenticatable directive in the given model, plus accessors. Also generate migration for ActiveRecord"

      def inject_devise_twilio_verify_content
        path = File.join(destination_root, "app", "models", "#{file_path}.rb")
        if File.exist?(path) &&
           !File.read(path).include?("twilio_verify_authenticatable")
          inject_into_file(path,
                           "twilio_verify_authenticatable, :",
                           :after => "devise :")
        end

        if File.exist?(path) &&
           !File.read(path).include?(":authy_id")
          inject_into_file(path,
                           ":twilio_totp_factor_sid, :last_sign_in_with_twilio_verify, ",
                           :after => "attr_accessible ")
        end
      end

      hook_for :orm
    end
  end
end
