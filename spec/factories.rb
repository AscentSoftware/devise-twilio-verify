# frozen_string_literal: true

FactoryBot.define do
  sequence :email do |n|
    "person#{n}@example.com"
  end

  sequence :twilio_totp_factor_sid do |n|
    n.to_s
  end

  factory :user do
    email { generate(:email) }
    password { "correct horse battery staple" }
    mobile_phone { '1234567890'}

    factory :twilio_verify_user do
      twilio_totp_factor_sid { generate(:twilio_totp_factor_sid) }
      twilio_verify_enabled { true }
    end
  end

  factory :lockable_user, class: LockableUser do
    email { generate(:email) }
    password { "correct horse battery staple" }
  end

  factory :lockable_twilio_verify_user, class: LockableUser do
    email { generate(:email) }
    password { "correct horse battery staple" }
    twilio_totp_factor_sid { generate(:twilio_totp_factor_sid) }
    twilio_verify_enabled { true }
    mobile_phone { '1234567890'}
  end

  factory :user_with_telephone, class: User do
    email { generate(:email) }
    password { "correct horse battery staple" }
    telephone { '1231231231'}
  end
end
