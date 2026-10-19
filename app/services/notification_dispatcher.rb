class NotificationDispatcher
  class << self
    def reservation_confirmed(reservation)
      recipients = reservation.company.memberships.active.joins(:membership_roles)
        .where(membership_roles: { role: "admin" }).includes(:user).map(&:user)
      recipients << reservation.seller_membership.user if reservation.seller_membership
      dispatch(recipients.uniq, company: reservation.company, event_type: "reservation_confirmed",
        title: "Reserva #{reservation.code} confirmada",
        body: "#{reservation.passengers.size} pasajero(s) ocuparon cupos en #{reservation.departure_offer.travel_package.name}.",
        action_url: Rails.application.routes.url_helpers.reservation_path(reservation))
    end

    def offer_published(offer)
      recipients = offer.company.memberships.active.joins(:membership_roles)
        .where(membership_roles: { role: "reseller" }).includes(:user).map(&:user)
      dispatch(recipients, company: offer.company, event_type: "offer_published",
        title: "Nuevo viaje publicado", body: offer.travel_package.name,
        action_url: Rails.application.routes.url_helpers.departure_offer_path(offer))
    end

    def fare_changed(offer, old_cents, new_cents)
      recipients = offer.company.memberships.active.joins(:membership_roles)
        .where(membership_roles: { role: "reseller" }).includes(:user).map(&:user)
      dispatch(recipients, company: offer.company, event_type: "fare_changed",
        title: "Precio actualizado: #{offer.travel_package.name}",
        body: "#{MoneyFormatter.call(old_cents)} → #{MoneyFormatter.call(new_cents)}",
        action_url: Rails.application.routes.url_helpers.departure_offer_path(offer))
    end

    def dispatch(users, company:, event_type:, title:, body:, action_url: nil)
      event_id = SecureRandom.uuid
      users.each do |user|
        notification = Notification.create_or_find_by!(user:, deduplication_key: "#{event_type}:#{event_id}") do |record|
          record.assign_attributes(company:, event_type:, title:, body:, action_url:)
        end
        DeliverNotificationJob.perform_later(notification.id)
      end
    end
  end
end
