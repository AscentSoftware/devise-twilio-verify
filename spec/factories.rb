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
    mobile_phone { '+441234567800'} # UK

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
    mobile_phone { '+1 617-525-3078'} # US
  end

  factory :user_with_telephone, class: User do
    email { generate(:email) }
    password { "correct horse battery staple" }
    telephone { '+61 414 123 456'} # AU
  end
end
