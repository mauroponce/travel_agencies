class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAILER_FROM", "#{ENV.fetch('PLATFORM_NAME', 'Turistack')} <no-reply@turistack.com>") }
  layout "mailer"
end
