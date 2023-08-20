# frozen_string_literal: true

RSpec.describe Devise::DeviseTwilioVerifyController, type: :controller do
  let(:user) { create(:twilio_verify_user) }
  before(:each) { request.env["devise.mapping"] = Devise.mappings[:user] }

  describe "first step of authentication not complete" do
    describe "with no user details in the session" do
      describe "#GET_verify_twilio_verify" do
        it "should redirect to the root_path" do
          get :GET_verify_twilio_verify
          expect(response).to redirect_to(root_path)
        end
      end

      describe "#POST_verify_twilio_verify" do
        it "should redirect to the root_path" do
          post :POST_verify_twilio_verify
          expect(response).to redirect_to(root_path)
        end

        it "should not verify a token" do
          expect(TwilioVerifyService).not_to receive(:fake_totp_verify)
          expect(TwilioVerifyService).not_to receive(:verify_totp_token)
          post :POST_verify_twilio_verify
        end
      end
    end

    describe "without checking the password" do
      before(:each) { request.session["user_id"] = user.id }

      describe "#GET_verify_twilio_verify" do
        it "should redirect to the root_path" do
          get :GET_verify_twilio_verify
          expect(response).to redirect_to(root_path)
        end
      end

      describe "#POST_verify_twilio_verify" do
        it "should redirect to the root_path" do
          post :POST_verify_twilio_verify
          expect(response).to redirect_to(root_path)
        end

        it "should not verify a token" do
          expect(TwilioVerifyService).not_to receive(:fake_totp_verify)
          expect(TwilioVerifyService).not_to receive(:verify_totp_token)
          post :POST_verify_twilio_verify
        end
      end
    end
  end

  describe "when the first step of authentication is complete" do
    before do
      request.session["user_id"] = user.id
      request.session["user_password_checked"] = true
    end

    describe "GET #verify_twilio_verify" do
      it "Should render the second step of authentication" do
        get :GET_verify_twilio_verify
        expect(response).to render_template('verify_twilio_verify')
      end
    end

    describe "POST #verify_twilio_verify" do
      let(:verify_success) { double("Twilio::Verify::Response", status: 'approved') }
      let(:verify_failure) { double("Twilio::Verify::Response", status: 'failed') }
      let(:valid_twilio_verify_token) { rand(0..999999).to_s.rjust(6, '0') }
      let(:invalid_twilio_verify_token) { rand(0..999999).to_s.rjust(6, '0') }

      describe "when Rails is running in development" do
        before do
          allow(Rails).to receive(:env) { double(development?: true, test?: false) }
        end

        describe "with fake token" do
          let(:params) do
            {
              token: ENV['FAKE_TWILIO_VERIFY_TOKEN']
            }
          end

          before(:each) do
            expect(TwilioVerifyService).to(
              receive(:build_v2_client).never
            )
            post :POST_verify_twilio_verify, params: params
          end

          it "should log the user in" do
            expect(subject.current_user).to eq(user)
            expect(session["user_twilio_verify_token_checked"]).to be true
          end

          context "with a fake token set via ENV setting" do
            around do |example|
              ENV['FAKE_TWILIO_VERIFY_TOKEN'] = '123123'
              example.run
              ENV['FAKE_TWILIO_VERIFY_TOKEN'] = '0000000'
            end

            let(:params) do
              {
                token: '123123'
              }
            end

            it "should log the user in" do
              expect(subject.current_user).to eq(user)
              expect(session["user_twilio_verify_token_checked"]).to be true
            end
          end

          it "should set the last_sign_in_with_twilio_verify field on the user" do
            expect(user.last_sign_in_with_twilio_verify).to be_nil
            user.reload
            expect(user.last_sign_in_with_twilio_verify).not_to be_nil
            expect(user.last_sign_in_with_twilio_verify).to be_within(1).of(Time.zone.now)
          end

          it "should redirect to the root_path and set a flash notice" do
            expect(response).to redirect_to(root_path)
            expect(flash[:notice]).not_to be_nil
            expect(flash[:error]).to be nil
          end

          it "should not set a remember_device cookie" do
            expect(cookies["remember_device"]).to be_nil
          end

          it "should not remember the user" do
            user.reload
            expect(user.remember_created_at).to be nil
          end
        end

        describe "with fake token and remember_me in the session" do
          let(:params) do
            {
              token: ENV['FAKE_TWILIO_VERIFY_TOKEN']
            }
          end

          before(:each) do
            request.session["user_remember_me"] = true
            expect(TwilioVerifyService).to(
              receive(:build_v2_client).never
            )
            post :POST_verify_twilio_verify, params: params
          end

          it "should remember the user" do
            user.reload
            expect(user.remember_created_at).to be_within(1).of(Time.zone.now)
          end
        end

        describe "with fake token and remember device selected" do
          let(:params) do
            {
              token: ENV['FAKE_TWILIO_VERIFY_TOKEN'], remember_device: '1'
            }
          end

          before(:each) do
            expect(TwilioVerifyService).to(
              receive(:build_v2_client).never
            )
            post :POST_verify_twilio_verify, params: params
          end

          it "should set a signed remember_device cookie" do
            jar = ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
            cookie = jar.signed["remember_device"]
            expect(cookie).not_to be_nil
            parsed_cookie = JSON.parse(cookie)
            expect(parsed_cookie["id"]).to eq(user.id)
          end
        end

        describe "with an invalid token" do
          before(:each) {
            expect(TwilioVerifyService).to(
              receive(:build_v2_client).never
            )
            post :POST_verify_twilio_verify, params: { :token => invalid_twilio_verify_token }
          }

          it "Shouldn't log the user in" do
            expect(subject.current_user).to be nil
          end

          it "should redirect to the verification page" do
            expect(response).to render_template('verify_twilio_verify')
          end

          it "should set an error message in the flash" do
            expect(flash[:notice]).to be nil
            expect(flash[:error]).not_to be nil
          end
        end
      end

      describe "when fake api is on" do
        around do |example|
          ENV['FAKE_TWILIO_VERIFY_API'] = '1'
          example.run
          ENV['FAKE_TWILIO_VERIFY_API'] = nil
        end

        describe "with fake token" do
          let(:params) do
            {
              token: ENV['FAKE_TWILIO_VERIFY_TOKEN']
            }
          end

          before(:each) do
            expect(TwilioVerifyService).to(
              receive(:build_v2_client).never
            )
            post :POST_verify_twilio_verify, params: params
          end

          it "should log the user in" do
            expect(subject.current_user).to eq(user)
            expect(session["user_twilio_verify_token_checked"]).to be true
          end

          it "should set the last_sign_in_with_twilio_verify field on the user" do
            expect(user.last_sign_in_with_twilio_verify).to be_nil
            user.reload
            expect(user.last_sign_in_with_twilio_verify).not_to be_nil
            expect(user.last_sign_in_with_twilio_verify).to be_within(1).of(Time.zone.now)
          end

          it "should redirect to the root_path and set a flash notice" do
            expect(response).to redirect_to(root_path)
            expect(flash[:notice]).not_to be_nil
            expect(flash[:error]).to be nil
          end

          it "should not set a remember_device cookie" do
            expect(cookies["remember_device"]).to be_nil
          end

          it "should not remember the user" do
            user.reload
            expect(user.remember_created_at).to be nil
          end
        end

        describe "with fake token and remember_me in the session" do
          let(:params) do
            {
              token: ENV['FAKE_TWILIO_VERIFY_TOKEN']
            }
          end

          before(:each) do
            request.session["user_remember_me"] = true
            expect(TwilioVerifyService).to(
              receive(:build_v2_client).never
            )
            post :POST_verify_twilio_verify, params: params
          end

          it "should remember the user" do
            user.reload
            expect(user.remember_created_at).to be_within(1).of(Time.zone.now)
          end
        end

        describe "with fake token and remember device selected" do
          let(:params) do
            {
              token: ENV['FAKE_TWILIO_VERIFY_TOKEN'], remember_device: '1'
            }
          end

          before(:each) do
            expect(TwilioVerifyService).to(
              receive(:build_v2_client).never
            )
            post :POST_verify_twilio_verify, params: params
          end

          it "should set a signed remember_device cookie" do
            jar = ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
            cookie = jar.signed["remember_device"]
            expect(cookie).not_to be_nil
            parsed_cookie = JSON.parse(cookie)
            expect(parsed_cookie["id"]).to eq(user.id)
          end
        end

        describe "with an invalid token" do
          before(:each) {
            expect(TwilioVerifyService).to(
              receive(:build_v2_client).never
            )
            post :POST_verify_twilio_verify, params: { :token => invalid_twilio_verify_token }
          }

          it "Shouldn't log the user in" do
            expect(subject.current_user).to be nil
          end

          it "should redirect to the verification page" do
            expect(response).to render_template('verify_twilio_verify')
          end

          it "should set an error message in the flash" do
            expect(flash[:notice]).to be nil
            expect(flash[:error]).not_to be nil
          end
        end
      end

      describe "with a valid token" do
        before(:each) {
          expect(TwilioVerifyService).to(
            receive(:verify_totp_token)
              .with(user, valid_twilio_verify_token)
              .and_return(verify_success)
          )
        }

        describe "without remembering" do
          before(:each) {
            post :POST_verify_twilio_verify, params: { :token => valid_twilio_verify_token }
          }

          it "should log the user in" do
            expect(subject.current_user).to eq(user)
            expect(session["user_twilio_verify_token_checked"]).to be true
          end

          it "should set the last_sign_in_with_twilio_verify field on the user" do
            expect(user.last_sign_in_with_twilio_verify).to be_nil
            user.reload
            expect(user.last_sign_in_with_twilio_verify).not_to be_nil
            expect(user.last_sign_in_with_twilio_verify).to be_within(1).of(Time.zone.now)
          end

          it "should redirect to the root_path and set a flash notice" do
            expect(response).to redirect_to(root_path)
            expect(flash[:notice]).not_to be_nil
            expect(flash[:error]).to be nil
          end

          it "should not set a remember_device cookie" do
            expect(cookies["remember_device"]).to be_nil
          end

          it "should not remember the user" do
            user.reload
            expect(user.remember_created_at).to be nil
          end
        end

        describe "and remember device selected" do
          before(:each) {
            post :POST_verify_twilio_verify, params: {
              token: valid_twilio_verify_token,
              remember_device: '1'
            }
          }

          it "should set a signed remember_device cookie" do
            jar = ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
            cookie = jar.signed["remember_device"]
            expect(cookie).not_to be_nil
            parsed_cookie = JSON.parse(cookie)
            expect(parsed_cookie["id"]).to eq(user.id)
          end
        end

        describe "and remember_me in the session" do
          before(:each) do
            request.session["user_remember_me"] = true
            post :POST_verify_twilio_verify, params: { token: valid_twilio_verify_token }
          end

          it "should remember the user" do
            user.reload
            expect(user.remember_created_at).to be_within(1).of(Time.zone.now)
          end
        end
      end

      describe "with an invalid token" do
        before(:each) {
          expect(TwilioVerifyService).to(
            receive(:verify_totp_token)
              .with(user, invalid_twilio_verify_token)
              .and_return(verify_failure)
          )
          post :POST_verify_twilio_verify, params: { :token => invalid_twilio_verify_token }
        }

        it "Shouldn't log the user in" do
          expect(subject.current_user).to be nil
        end

        it "should redirect to the verification page" do
          expect(response).to render_template('verify_twilio_verify')
        end

        it "should set an error message in the flash" do
          expect(flash[:notice]).to be nil
          expect(flash[:error]).not_to be nil
        end
      end

      describe 'with a lockable user' do
        let(:lockable_user) { create(:lockable_twilio_verify_user) }
        before(:all) { Devise.lock_strategy = :failed_attempts }

        before(:each) do
          request.session["user_id"] = lockable_user.id
          request.session["user_password_checked"] = true
        end

        it 'locks the account when failed_attempts exceeds maximum' do
          expect(TwilioVerifyService).to(
            receive(:verify_totp_token)
              .exactly(Devise.maximum_attempts)
              .with(lockable_user, invalid_twilio_verify_token)
              .and_return(verify_failure)
          )
          (Devise.maximum_attempts).times do
            post :POST_verify_twilio_verify, params: { token: invalid_twilio_verify_token }
          end

          lockable_user.reload
          expect(lockable_user.access_locked?).to be true
        end
      end

      describe 'with a user that is not lockable' do
        it 'does not lock the account when failed_attempts exceeds maximum' do
          request.session['user_id']               = user.id
          request.session['user_password_checked'] = true

          expect(TwilioVerifyService).to(
            receive(:verify_totp_token)
              .exactly(Devise.maximum_attempts)
              .with(user, invalid_twilio_verify_token)
              .and_return(verify_failure)
          )

          Devise.maximum_attempts.times do
            post :POST_verify_twilio_verify, params: { token: invalid_twilio_verify_token }
          end

          user.reload
          expect(user.locked_at).to be_nil
        end
      end
    end
  end

  describe "enabling/disabling twilio_verify" do
    describe "with no-one logged in" do
      it "GET #enable_twilio_verify should redirect to sign in" do
        get :GET_enable_twilio_verify
        expect(response).to redirect_to(new_user_session_path)
      end

      it "POST #enable_twilio_verify should redirect to sign in" do
        post :POST_enable_twilio_verify
        expect(response).to redirect_to(new_user_session_path)
      end

      it "GET #verify_twilio_verify_installation should redirect to sign in" do
        get :GET_verify_twilio_verify_installation
        expect(response).to redirect_to(new_user_session_path)
      end

      it "POST #verify_twilio_verify_installation should redirect to sign in" do
        post :POST_verify_twilio_verify_installation
        expect(response).to redirect_to(new_user_session_path)
      end

      it "POST #disable_twilio_verify should redirect to sign in" do
        post :POST_disable_twilio_verify
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    describe "with a logged in user" do
      let(:enable_success) do
        double(
          "Twilio::Verify::Response",
          status: 'unverified', sid: 'YF123456',
          binding: { 'uri' => 'https://example.com/qr.png' }
        )
      end
      let(:enable_failure) { double("Twilio::Verify::Response", status: 'failed', sid: nil) }

      before(:each) { sign_in(user) }

      describe "GET #enable_twilio_verify" do
        it "should render enable twilio_verify view if user isn't enabled" do
          user.update_attribute(:twilio_verify_enabled, false)
          get :GET_enable_twilio_verify
          expect(response).to render_template("enable_twilio_verify")
        end

        it "should render enable twilio_verify view if user doesn't have an twilio_totp_factor_sid" do
          user.update_attribute(:twilio_totp_factor_sid, nil)
          get :GET_enable_twilio_verify
          expect(response).to render_template("enable_twilio_verify")
        end

        it "should redirect and set flash if twilio_verify is enabled" do
          user.update_attribute(:twilio_verify_enabled, true)
          get :GET_enable_twilio_verify
          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).not_to be nil
        end
      end

      describe "POST #enable_twilio_verify" do
        let(:user) { create(:user, twilio_totp_factor_sid: 'dummy') }
        let(:cellphone) { '3010008090' } # TODO currently ignored
        let(:country_code) { '57' } # TODO currently ignored

        describe "when Rails is running in development" do
          before do
            allow(Rails).to receive(:env) { double(development?: true, test?: false) }
          end

          before(:each) do
            expect(TwilioVerifyService).to(
              receive(:build_v2_client).never
            )
            post :POST_enable_twilio_verify, params: { cellphone: cellphone, country_code: country_code }
          end

          it "save the twilio_totp_factor_sid to the user" do
            user.reload
            expect(user.twilio_totp_factor_sid).to eq('YF-DEV-SID')
            expect(user.twilio_totp_seed).to eq('otpauth://totp/test-issuer:test?secret=test&issuer=test&algorithm' \
                                                '=SHA1&digits=6&period=30')
          end

          it "should not enable the user yet" do
            user.reload
            expect(user.twilio_verify_enabled).to be(false)
          end

          it "should redirect to the verification page" do
            expect(response).to redirect_to(user_verify_twilio_verify_installation_path)
          end
        end

        describe "when fake api is on" do
          around do |example|
            ENV['FAKE_TWILIO_VERIFY_API'] = '1'
            example.run
            ENV['FAKE_TWILIO_VERIFY_API'] = nil
          end

          before(:each) do
            expect(TwilioVerifyService).to(
              receive(:build_v2_client).never
            )
            post :POST_enable_twilio_verify, params: { cellphone: cellphone, country_code: country_code }
          end

          it "save the twilio_totp_factor_sid to the user" do
            user.reload
            expect(user.twilio_totp_factor_sid).to eq('YF-DEV-SID')
            expect(user.twilio_totp_seed).to eq('otpauth://totp/test-issuer:test?secret=test&issuer=test&algorithm' \
                                                '=SHA1&digits=6&period=30')
          end

          it "should not enable the user yet" do
            user.reload
            expect(user.twilio_verify_enabled).to be(false)
          end

          it "should redirect to the verification page" do
            expect(response).to redirect_to(user_verify_twilio_verify_installation_path)
          end
        end

        describe "with a successful registration for TOTP" do
          before(:each) do
            expect(TwilioVerifyService).to(
              receive(:register_totp_service)
                .with(user)
                .and_return(enable_success)
            )
            post :POST_enable_twilio_verify, :params => { :cellphone => cellphone, :country_code => country_code }
          end

          it "save the twilio_totp_factor_sid to the user" do
            user.reload
            expect(user.twilio_totp_factor_sid).to eq('YF123456')
            expect(user.twilio_totp_seed).to eq('https://example.com/qr.png')
          end

          it "should not enable the user yet" do
            user.reload
            expect(user.twilio_verify_enabled).to be(false)
          end

          it "should redirect to the verification page" do
            expect(response).to redirect_to(user_verify_twilio_verify_installation_path)
          end
        end

        describe "but a user that can't be saved" do
          before(:each) do
            expect(user).to receive(:save).and_return(false)
            expect(subject).to receive(:current_user).and_return(user)
            expect(TwilioVerifyService).to(
              receive(:register_totp_service)
                .with(user)
                .and_return(enable_success)
            )
            post :POST_enable_twilio_verify, :params => { :cellphone => cellphone, :country_code => country_code }
          end

          it "should set an error flash" do
            expect(flash[:error]).not_to be nil
          end

          it "should redirect" do
            expect(response).to redirect_to(root_path)
          end
        end

        describe "with an unsuccessful registration for TOTP" do
          before(:each) do
            expect(TwilioVerifyService).to(
              receive(:register_totp_service)
                .with(user)
                .and_return(enable_failure)
            )

            post :POST_enable_twilio_verify, :params => { :cellphone => cellphone, :country_code => country_code }
          end

          it "does not update the twilio_totp_factor_sid" do
            user.reload
            expect(user.twilio_totp_factor_sid).to eq('dummy')
            expect(user.twilio_totp_seed).to be_nil
          end

          it "shows an error flash" do
            expect(flash[:error]).to eq("Something went wrong while enabling two factor authentication")
          end

          it "renders enable_twilio_verify page again" do
            expect(response).to render_template('enable_twilio_verify')
          end
        end
      end

      describe "GET verify_twilio_verify_installation" do
        let(:qr_code_obj) { double('RQRCode::QRCode', as_svg: 'some-svg') }

        before do
          allow(RQRCode::QRCode).to receive(:new) { qr_code_obj }
        end

        describe "with a user that hasn't enabled twilio_verify yet" do
          let(:user) { create(:user) }
          before(:each) { sign_in(user) }

          it "should redirect to enable twilio_verify" do
            get :GET_verify_twilio_verify_installation
            expect(response).to redirect_to user_enable_twilio_verify_path
          end
        end

        describe "with a user that has enabled twilio_verify" do
          it "should redirect to after twilio_verify verified path" do
            get :GET_verify_twilio_verify_installation
            expect(response).to redirect_to root_path
          end
        end

        describe "with a user with a totp factor sid without twilio_verify enabled" do
          before(:each) do
            user.update(twilio_verify_enabled: false, twilio_totp_seed: 'some-seed')
          end

          it "should render the twilio_verify verification page" do
            get :GET_verify_twilio_verify_installation
            expect(response).to render_template('verify_twilio_verify_installation')
          end

          it "should generate a QR code as svg" do
            get :GET_verify_twilio_verify_installation
            expect(response).to render_template('verify_twilio_verify_installation')
            expect(assigns[:qr_code]).to eq('some-svg')
          end
        end
      end

      describe "POST verify_twilio_verify_installation" do
        let(:token) { ENV['FAKE_TWILIO_VERIFY_TOKEN'] }
        let(:verify_success) { double("Twilio::Verify::Response", status: 'verified') }
        let(:verify_failure) { double("Twilio::Verify::Response", status: 'failed') }
        let(:qr_code_obj) { double('RQRCode::QRCode', as_svg: 'some-svg') }

        before do
          allow(RQRCode::QRCode).to receive(:new) { qr_code_obj }
        end

        describe "with a user without a totp factor sid" do
          let(:user) { create(:user) }

          it "redirects to enable path" do
            post :POST_verify_twilio_verify_installation, params: { token: token }
            expect(response).to redirect_to(user_enable_twilio_verify_path)
          end
        end

        describe "with a user that has an totp factor sid and is enabled" do
          it "redirects to after twilio_verify verified path" do
            post :POST_verify_twilio_verify_installation, :params => { :token => token }
            expect(response).to redirect_to(root_path)
          end
        end

        describe "with a user that has a totp factor sid but isn't enabled" do
          before(:each) { user.update_attribute(:twilio_verify_enabled, false) }

          describe "when Rails is running in development" do
            before do
              allow(Rails).to receive(:env) { double(development?: true, test?: false) }
            end

            before(:each) do
              expect(TwilioVerifyService).to(
                receive(:build_v2_client).never
              )
              post :POST_verify_twilio_verify_installation, :params => { :token => token, :remember_device => '0' }
            end

            it "should enable twilio_verify for user" do
              user.reload
              expect(user.twilio_verify_enabled).to be true
            end

            it "should set {resource}_twilio_verify_token_checked in the session" do
              expect(session['user_twilio_verify_token_checked']).to be true
            end

            it "should set a flash notice and redirect" do
              expect(response).to redirect_to(root_path)
              expect(flash[:notice]).to eq('Two factor authentication was enabled')
            end

            it "should not set a remember_device cookie" do
              expect(cookies['remember_device']).to be_nil
            end
          end

          describe "when fake api is on" do
            around do |example|
              ENV['FAKE_TWILIO_VERIFY_API'] = '1'
              example.run
              ENV['FAKE_TWILIO_VERIFY_API'] = nil
            end

            before(:each) do
              expect(TwilioVerifyService).to(
                receive(:build_v2_client).never
              )
              post :POST_verify_twilio_verify_installation, :params => { :token => token, :remember_device => '0' }
            end

            it "should enable twilio_verify for user" do
              user.reload
              expect(user.twilio_verify_enabled).to be true
            end

            it "should set {resource}_twilio_verify_token_checked in the session" do
              expect(session['user_twilio_verify_token_checked']).to be true
            end

            it "should set a flash notice and redirect" do
              expect(response).to redirect_to(root_path)
              expect(flash[:notice]).to eq('Two factor authentication was enabled')
            end

            it "should not set a remember_device cookie" do
              expect(cookies['remember_device']).to be_nil
            end
          end

          describe "successful verification" do
            before(:each) do
              expect(TwilioVerifyService).to(
                receive(:confirm_totp_service)
                  .with(user, token)
                  .and_return(verify_success)
              )
              post :POST_verify_twilio_verify_installation, :params => { :token => token, :remember_device => '0' }
            end

            it "should enable twilio_verify for user" do
              user.reload
              expect(user.twilio_verify_enabled).to be true
            end

            it "should set {resource}_twilio_verify_token_checked in the session" do
              expect(session['user_twilio_verify_token_checked']).to be true
            end

            it "should set a flash notice and redirect" do
              expect(response).to redirect_to(root_path)
              expect(flash[:notice]).to eq('Two factor authentication was enabled')
            end

            it "should not set a remember_device cookie" do
              expect(cookies['remember_device']).to be_nil
            end
          end

          describe "successful verification with remember device" do
            before(:each) do
              expect(TwilioVerifyService).to(
                receive(:confirm_totp_service)
                  .with(user, token)
                  .and_return(verify_success)
              )
              post :POST_verify_twilio_verify_installation, :params => { :token => token, :remember_device => '1' }
            end

            it "should enable twilio_verify for user" do
              user.reload
              expect(user.twilio_verify_enabled).to be true
            end

            it "should set {resource}_twilio_verify_token_checked in the session" do
              expect(session['user_twilio_verify_token_checked']).to be true
            end
            it "should set a flash notice and redirect" do
              expect(response).to redirect_to(root_path)
              expect(flash[:notice]).to eq('Two factor authentication was enabled')
            end

            it "should set a signed remember_device cookie" do
              jar = ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
              cookie = jar.signed['remember_device']
              expect(cookie).not_to be_nil
              parsed_cookie = JSON.parse(cookie)
              expect(parsed_cookie['id']).to eq(user.id)
            end
          end

          describe "unsuccessful verification" do
            before(:each) do
              expect(TwilioVerifyService).to(
                receive(:confirm_totp_service)
                  .with(user, token)
                  .and_return(verify_failure)
              )
              post :POST_verify_twilio_verify_installation, :params => { :token => token }
            end

            it "should not enable twilio_verify for user" do
              user.reload
              expect(user.twilio_verify_enabled).to be false
            end

            it "should set an error flash and render verify_twilio_verify_installation" do
              expect(response).to render_template('verify_twilio_verify_installation')
              expect(flash[:error]).to eq('Something went wrong while enabling two factor authentication')
              expect(assigns[:qr_code]).to eq('some-svg')
            end
          end
        end
      end

      describe "POST disable_twilio_verify" do
        let(:response_success) { double("Twilio::Verify::Response") }
        let(:user) { create(:twilio_verify_user) }

        describe "successfully" do
          before(:each) do
            cookies.signed[:remember_device] = {
              :value => { expires: Time.now.to_i, id: user.id }.to_json,
              :secure => false,
              :expires => User.twilio_verify_remember_device.from_now
            }
            expect(TwilioVerifyService).to receive(:delete_totp_service)
              .with(user)
              .and_return(response_success)

            post :POST_disable_twilio_verify
          end

          it "should disable 2FA" do
            user.reload
            expect(user.twilio_totp_factor_sid).to be nil
            expect(user.twilio_verify_enabled).to be false
          end

          it "should forget the device cookie" do
            expect(response.cookies[:remember_device]).to be nil
          end

          it "should set a flash notice and redirect" do
            expect(flash.now[:notice]).to eq("Two factor authentication was disabled")
            expect(response).to redirect_to(root_path)
          end
        end

        describe "with more than one user using the same totp factor sid" do
          before(:each) do
            create(:twilio_verify_user, twilio_totp_factor_sid: user.twilio_totp_factor_sid)
            cookies.signed[:remember_device] = {
              :value => { expires: Time.now.to_i, id: user.id }.to_json,
              :secure => false,
              :expires => User.twilio_verify_remember_device.from_now
            }
            expect(TwilioVerifyService).not_to receive(:delete_totp_service)

            post :POST_disable_twilio_verify
          end

          it "should disable 2FA" do
            user.reload
            expect(user.twilio_totp_factor_sid).to be nil
            expect(user.twilio_verify_enabled).to be false
          end

          it "should forget the device cookie" do
            expect(response.cookies[:remember_device]).to be nil
          end

          it "should set a flash notice and redirect" do
            expect(flash.now[:notice]).to eq("Two factor authentication was disabled")
            expect(response).to redirect_to(root_path)
          end
        end

        describe "unsuccessfully" do
          before(:each) do
            cookies.signed[:remember_device] = {
              :value => { expires: Time.now.to_i, id: user.id }.to_json,
              :secure => false,
              :expires => User.twilio_verify_remember_device.from_now
            }
            expect(TwilioVerifyService).to(
              receive(:delete_totp_service)
                .with(user)
                .and_raise(StandardError)
            )

            post :POST_disable_twilio_verify
          end

          it "should not disable 2FA" do
            user.reload
            expect(user.twilio_totp_factor_sid).not_to be nil
            expect(user.twilio_verify_enabled).to be true
          end

          it "should not forget the device cookie" do
            expect(cookies[:remember_device]).not_to be_nil
          end

          it "should set a flash error and redirect" do
            expect(flash[:error]).to eq("Something went wrong while disabling two factor authentication")
            expect(response).to redirect_to(root_path)
          end
        end
      end
    end
  end

  describe "requesting authentication tokens" do
    describe "without a user" do
      it "Should not request sms if user couldn't be found", pending: true do
        expect(TwilioVerifyService).not_to receive(:send_sms_token)

        post :request_sms

        expect(response.media_type).to eq('application/json')
        body = JSON.parse(response.body)
        expect(body['sent']).to be false
        expect(body['message']).to eq("User couldn't be found.")
      end
    end

    describe "#request_sms", pending: true do
      let(:verify_success) { double("Twilio::Verify::Response", status: 'pending') }
      let(:verify_failure) { double("Twilio::Verify::Response", status: 'failed') }

      before(:each) do
        expect(TwilioVerifyService).to(
          receive(:send_sms_token)
            .with(user.mobile_phone)
            .and_return(verify_success)
        )
      end

      describe "with a logged in user" do
        before(:each) { sign_in user }

        it "should send an SMS and respond with JSON" do
          post :request_sms
          expect(response.media_type).to eq('application/json')
          body = JSON.parse(response.body)

          expect(body['sent']).to be_truthy
          expect(body['message']).to eq('Token was sent.')
        end
      end

      describe "with a user_id in the session" do
        before(:each) { session['user_id'] = user.id }

        it "should send an SMS and respond with JSON" do
          post :request_sms
          expect(response.media_type).to eq('application/json')
          body = JSON.parse(response.body)

          expect(body['sent']).to be_truthy
          expect(body['message']).to eq 'Token was sent.'
        end
      end
    end
  end
end
