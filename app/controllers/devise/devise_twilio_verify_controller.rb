class Devise::DeviseTwilioVerifyController < DeviseController
  prepend_before_action :find_resource, only: [
    :request_sms
  ]
  prepend_before_action :find_resource_and_require_password_checked, only: [
    :GET_verify_twilio_verify, :POST_verify_twilio_verify
  ]

  prepend_before_action :check_resource_not_twilio_verify_enabled, only: [
    :GET_verify_twilio_verify_installation, :POST_verify_twilio_verify_installation
  ]

  prepend_before_action :authenticate_scope!, only: [
    :GET_enable_twilio_verify, :POST_enable_twilio_verify, :GET_verify_twilio_verify_installation,
    :POST_verify_twilio_verify_installation, :POST_disable_twilio_verify
  ]

  include Devise::Controllers::Helpers

  def GET_verify_twilio_verify
    render :verify_twilio_verify
  end

  # verify 2fa
  def POST_verify_twilio_verify
    handle_invalid_token(:verify_twilio_verify, :invalid_token) and return if params[:token].blank?

    # begin
    #   verification_check = TwilioVerifyService.verify_sms_token(@resource.mobile_phone, params[:token])
    #   verification_check = verification_check.status == 'approved'
    # rescue Twilio::REST::RestError
    #   verification_check = false
    # end

    verification_check = TwilioVerifyService.verify_totp_token(@resource, params[:token])

    if verification_check.status == 'approved'
      remember_device(@resource.id) if params[:remember_device].to_i == 1
      remember_user
      record_twilio_verify_authentication
      respond_with @resource, location: after_sign_in_path_for(@resource)
    else
      handle_invalid_token :verify_twilio_verify, :invalid_token
    end
  end
  
  def GET_enable_twilio_verify
    render :enable_twilio_verify and return unless resource.with_twilio_verify_authentication?(request)

    set_flash_message(:notice, :already_enabled)
    redirect_to after_twilio_verify_enabled_path_for(resource)
  end

  # enable 2fa
  def POST_enable_twilio_verify
    totp_factor = TwilioVerifyService.register_totp_service(resource)

    if totp_factor.sid.blank?
      set_flash_message(:error, :not_enabled)
      render :enable_twilio_verify and return
    end

    args = {
      twilio_totp_factor_sid: totp_factor.sid,
      twilio_totp_seed: totp_factor.binding['uri']
    }
    redirect_to [resource_name, :verify_twilio_verify_installation] and return if resource.update(**args)

    flash[:error] = resource.errors.full_messages.join(', ')
    redirect_to after_twilio_verify_enabled_path_for(resource)
  end

  # Disable 2FA
  def POST_disable_twilio_verify
    twilio_totp_factor_sid = resource.twilio_totp_factor_sid
    twilio_totp_seed = resource.twilio_totp_seed
    resource.assign_attributes(
      twilio_verify_enabled: false, twilio_totp_factor_sid: nil, twilio_totp_seed: nil
    )
    resource.save(validate: false)

    other_resource = resource.class.find_by(twilio_totp_factor_sid: twilio_totp_factor_sid)
    if other_resource
      # If another resource has the same twilio_totp_factor_sid, do not delete the user from
      # the API.
      forget_device
      set_flash_message(:notice, :disabled)
    else
      begin
        TwilioVerifyService.delete_totp_service(resource)
        forget_device
        set_flash_message(:notice, :disabled)
      rescue StandardError => _err
        # If deleting the user from the API fails, set everything back to what
        # it was before.
        resource.assign_attributes(
          twilio_verify_enabled: true,
          twilio_totp_factor_sid: twilio_totp_factor_sid,
          twilio_totp_seed: twilio_totp_seed
        )
        resource.save(validate: false)
        set_flash_message(:error, :not_disabled)
      end
    end
    redirect_to after_twilio_verify_disabled_path_for(resource)
  end

  def GET_verify_twilio_verify_installation
    generate_qr_code_if_needed
    render :verify_twilio_verify_installation
  end

  def POST_verify_twilio_verify_installation
    if params[:token].blank?
      return handle_invalid_token :verify_twilio_verify_installation, :not_enabled
    end

    verification_check = TwilioVerifyService.confirm_totp_service(resource, params[:token])
    resource.twilio_verify_enabled = verification_check.status == 'verified'

    if resource.twilio_verify_enabled? && resource.save
      remember_device(resource.id) if params[:remember_device].to_i == 1
      record_twilio_verify_authentication
      set_flash_message(:notice, :enabled)
      redirect_to after_twilio_verify_verified_path_for(resource)
    else
      generate_qr_code_if_needed
      handle_invalid_token :verify_twilio_verify_installation, :not_enabled
    end
  end

  def request_sms
    sms_2fa_not_applicable and return unless Devise.twilio_verify_type == :sms
    user_not_found and return if resource.blank? || resource.mobile_phone.blank?
    mobile_phone_invalid and return unless resource.mobile_phone_valid?

    verification = TwilioVerifyService.send_sms_token(resource.mobile_phone)
    success = verification.status == 'pending'

    render json: {
      sent: success,
      message: success ? 'Token was sent.' : 'Token was not sent, please try again.'
    }
  end

  private

  def authenticate_scope!
    send(:"authenticate_#{resource_name}!", :force => true)
    self.resource = send("current_#{resource_name}")
    @resource = resource
  end

  def find_resource
    @resource = send("current_#{resource_name}")
    @resource = resource_class.find_by_id(session["#{resource_name}_id"]) if @resource.nil?
  end

  def find_resource_and_require_password_checked
    find_resource

    if @resource.nil? || session[:"#{resource_name}_password_checked"].to_s != "true"
      redirect_to invalid_resource_path
    end
  end

  def check_resource_not_twilio_verify_enabled
    if resource.twilio_totp_factor_sid.blank?
      redirect_to [resource_name, :enable_twilio_verify]
    elsif resource.twilio_verify_enabled?
      redirect_to after_twilio_verify_verified_path_for(resource)
    end
  end

  protected

  def after_twilio_verify_enabled_path_for(resource)
    root_path
  end

  def after_twilio_verify_verified_path_for(resource)
    after_twilio_verify_enabled_path_for(resource)
  end

  def after_twilio_verify_disabled_path_for(resource)
    root_path
  end

  def invalid_resource_path
    root_path
  end

  def handle_invalid_token(view, error_message)
    if @resource.respond_to?(:invalid_twilio_verify_attempt!) && @resource.invalid_twilio_verify_attempt!
      after_account_is_locked
    else
      set_flash_message(:error, error_message)
      render view
    end
  end

  def after_account_is_locked
    sign_out_and_redirect @resource
  end

  def remember_user
    if session.delete("#{resource_name}_remember_me") == true && @resource.respond_to?(:remember_me=)
      @resource.remember_me = true
    end
  end

  def user_not_found
    render json: { sent: false, message: "User couldn't be found." }, status: 404
  end

  def sms_2fa_not_applicable
    render json: { sent: false, message: 'SMS based Two Factor Authentication not configured' }, status: 403
  end

  def mobile_phone_invalid
    render json: { sent: false, message: 'Mobile phone number is invalid' }, status: 400
  end

  def generate_qr_code_if_needed
    return unless resource_class.twilio_verify_enable_qr_code && resource.respond_to?(:twilio_totp_seed)

    @qr_code = RQRCode::QRCode.new(resource.twilio_totp_seed).as_svg(fill: :white, module_size: 5)
  end
end
