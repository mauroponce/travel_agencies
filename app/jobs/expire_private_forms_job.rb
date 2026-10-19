class ExpirePrivateFormsJob < ApplicationJob
  queue_as :default

  def perform
    PassengerForm.where(submitted_at: nil, revoked_at: nil).where("expires_at <= ?", Time.current)
      .update_all(revoked_at: Time.current, updated_at: Time.current)
  end
end
