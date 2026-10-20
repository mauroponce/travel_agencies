class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAILER_FROM", "#{ENV.fetch('PLATFORM_NAME', 'NexoViajes')} <no-reply@localhost>") }
  layout "mailer"
end
