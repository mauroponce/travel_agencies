class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAILER_FROM", "NexoViajes <no-reply@nexoviajes.local>") }
  layout "mailer"
end
