class TwilioVerifyService
  TOTP_VERIFY_OK = Struct.new(:status).new('approved')
  TOTP_VERIFY_FAILED = Struct.new(:status).new('failed')
  TOTP_REGISTER_OK =
    Struct.new(:sid, :binding)
          .new(
            'YF-DEV-SID',
            { 'uri' => 'otpauth://totp/test-issuer:test?secret=test&issuer=test&algorithm=SHA1&digits=6&period=30' }
          )
  TOTP_CONFIRM_OK = Struct.new(:status).new('verified')
  TOTP_CONFIRM_FAILED = Struct.new(:status).new('failed')

  attr_reader :twilio_client, :twilio_account_sid, :twilio_auth_token, :twilio_verify_service_sid

  class << self
    def send_sms_token(phone_number)
      build_client.verifications.create(to: phone_number, channel: 'sms')
    end

    def verify_sms_token(phone_number, token)
      build_client.verification_checks.create(to: phone_number, code: token)
    end

    def verify_totp_token(user, token)
      return fake_totp_verify(fake_verify(token)) if fake_twilio_verify_api?

      build_v2_client
        .entities(user.twilio_identifier)
        .challenges
        .create(auth_payload: token, factor_sid: user.twilio_totp_factor_sid)
    end

    def fake_totp_verify(result)
      result ? TOTP_VERIFY_OK : TOTP_VERIFY_FAILED
    end

    def register_totp_service(user)
      return fake_totp_register if fake_twilio_verify_api?

      build_v2_client
        .entities(user.twilio_identifier)
        .new_factors
        .create(friendly_name: user.to_s, factor_type: 'totp')
    end

    def fake_totp_register
      TOTP_REGISTER_OK
    end

    def confirm_totp_service(user, token)
      return fake_totp_confirm(fake_verify(token)) if fake_twilio_verify_api?

      # After user adds the app to their authenticator app, register the user by having them confirm a token
      # if this returns factor.status == 'verified', the user has been properly setup
      build_v2_client
        .entities(user.twilio_identifier)
        .factors(user.twilio_totp_factor_sid)
        .update(auth_payload: token)
    end

    def fake_totp_confirm(result)
      result ? TOTP_CONFIRM_OK : TOTP_CONFIRM_FAILED
    end

    def delete_totp_service(user)
      return if fake_twilio_verify_api?

      build_v2_client
         .entities(user.twilio_identifier)
         .factors(user.twilio_totp_factor_sid)
         .delete
    end

    def fake_verify(token)
      return unless fake_twilio_verify_api?

      token == fake_token
    end

    def fake_twilio_verify_api?
      Rails.env.development? || fake_api_on?
    end

    def fake_token
      ENV['FAKE_TWILIO_VERIFY_TOKEN'] || '0000000'
    end

    def fake_api_on?
      ENV['FAKE_TWILIO_VERIFY_API'].to_i.positive?
    end

    def build_v2_client
      new.twilio_verify_service_v2
    end

    def build_client
      new.twilio_verify_service
    end
  end

  def initialize
    @twilio_account_sid = ENV['TWILIO_ACCOUNT_SID'] || Rails.application.credentials.twilio_account_sid
    @twilio_auth_token = ENV['TWILIO_AUTH_TOKEN'] || Rails.application.credentials.twilio_auth_token
    @twilio_verify_service_sid =
      ENV['TWILIO_VERIFY_SERVICE_SID'] || Rails.application.credentials.twilio_verify_service_sid

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
