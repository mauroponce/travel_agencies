Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.font_src :self, :https, :data
    policy.img_src :self, :https, :data, :blob
    policy.object_src :none
    policy.script_src :self, :https
    policy.style_src :self, :https, :unsafe_inline
    policy.connect_src :self, :https
    policy.base_uri :self
    # Chrome applies form-action to redirects after POST, including OAuth hops.
    policy.form_action :self, -> { PlatformHosts.url(host: PlatformHosts.auth_host) }, "https://accounts.google.com"
    policy.frame_ancestors :none
  end
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_nonce_auto = true
end
