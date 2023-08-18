class TwilioVerifyService
  attr_reader :twilio_client, :twilio_account_sid, :twilio_auth_token, :twilio_verify_service_sid

  def self.send_sms_token(phone_number)
    new.twilio_verify_service.verifications.create(to: phone_number, channel: 'sms')
  end

  def self.verify_sms_token(phone_number, token)
    new.twilio_verify_service.verification_checks.create(to: phone_number, code: token)
  end

  def self.verify_totp_token(user, token)
    new.twilio_verify_service_v2
      .entities(user.twilio_identifier)
      .challenges
      .create(auth_payload: token, factor_sid: user.twilio_totp_factor_sid)
  end

  def self.register_totp_service(user)
    new.twilio_verify_service_v2
      .entities(user.twilio_identifier)
      .new_factors
      .create(friendly_name: user.to_s, factor_type: 'totp')
  end

  def self.confirm_totp_service(user, token)
    # After user adds the app to their authenticator app, register the user by having them confirm a token
    # if this returns factor.status == 'verified', the user has been properly setup
    new.twilio_verify_service_v2
      .entities(user.twilio_identifier)
      .factors(user.twilio_totp_factor_sid)
      .update(auth_payload: token)
  end

  def self.delete_totp_service(user)
    new.twilio_verify_service_v2
       .entities(user.twilio_identifier)
       .factors(user.twilio_totp_factor_sid)
       .delete
  end

  def initialize
    @twilio_account_sid = Rails.application.credentials.twilio_account_sid || ENV['TWILIO_ACCOUNT_SID']
    @twilio_auth_token = Rails.application.credentials.twilio_auth_token || ENV['TWILIO_AUTH_TOKEN']
    @twilio_verify_service_sid = Rails.application.credentials.twilio_verify_service_sid || ENV['TWILIO_VERIFY_SERVICE_SID']

    raise 'Missing Twilio credentials' unless @twilio_account_sid && @twilio_auth_token && @twilio_verify_service_sid

    @twilio_client = Twilio::REST::Client.new(@twilio_account_sid, @twilio_auth_token)
  end

  def twilio_verify_service
    twilio_client.verify.services(twilio_verify_service_sid)
  end

  def twilio_verify_service_v2
    twilio_client.verify.v2.services(twilio_verify_service_sid)
  end
end
