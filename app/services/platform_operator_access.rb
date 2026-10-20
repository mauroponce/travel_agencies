require "set"

module PlatformOperatorAccess
  module_function

  def allowed?(user_or_email)
    email = user_or_email.respond_to?(:email) ? user_or_email.email : user_or_email
    allowed_emails.include?(email.to_s.strip.downcase)
  end

  def synchronize!(user)
    if allowed?(user)
      user.platform_roles.find_or_create_by!(role: "operator")
    else
      user.platform_roles.where(role: "operator").delete_all
    end
  end

  def allowed_emails
    ENV.fetch("PLATFORM_ADMIN_GOOGLE_EMAILS", "").split(",").filter_map do |email|
      email.strip.downcase.presence
    end.to_set
  end
end
