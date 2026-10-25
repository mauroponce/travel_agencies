require Rails.root.join("lib/turistack/runtime_configuration")

unless ENV["SECRET_KEY_BASE_DUMMY"] == "1"
  Turistack::RuntimeConfiguration.validate!
end
