class DeviseTwilioVerifyAddTo<%= table_name.camelize %> < ActiveRecord::Migration<%= migration_version %>
  def self.up
    change_table :<%= table_name %> do |t|
      t.string    :twilio_totp_factor_sid
      t.text    :twilio_totp_seed
      t.datetime  :last_sign_in_with_twilio_verify
      t.boolean   :twilio_verify_enabled, :default => false
    end

    add_index :<%= table_name %>, :authy_id
  end

  def self.down
    change_table :<%= table_name %> do |t|
      t.remove :twilio_totp_factor_sid, :last_sign_in_with_twilio_verify, :twilio_verify_enabled
    end
  end
end

