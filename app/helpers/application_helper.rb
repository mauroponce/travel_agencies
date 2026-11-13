module ApplicationHelper
  def agent_access = Agent::Access.new(current_agent_workspace)
  def argentine_date(value)
    return if value.blank?
    date = value.respond_to?(:strftime) ? value : Date.iso8601(value.to_s)
    date.strftime("%d/%m/%Y")
  rescue ArgumentError
    nil
  end

  def argentine_date_field(form, method, datetime: false, **options)
    value = options.key?(:value) ? options.delete(:value) : form.object&.public_send(method)
    argentine_date_field_tag(form.field_name(method), value, datetime:, id: form.field_id(method), **options)
  end

  def argentine_date_field_tag(name, value = nil, datetime: false, **options)
    id = options.delete(:id) || name.to_s.delete("]").tr("[", "_")
    date = value.presence
    if date.is_a?(String)
      date = begin
        datetime ? Time.iso8601(date) : Date.iso8601(date)
      rescue ArgumentError
        nil
      end
    end
    render "shared/argentine_date_field", name:, id:, datetime:, options:,
      iso_value: date&.strftime(datetime ? "%Y-%m-%dT%H:%M" : "%Y-%m-%d"),
      display_value: date&.strftime(datetime ? "%d/%m/%Y %H:%M" : "%d/%m/%Y")
  end

  def agent_signup_available?
    Current.host_scope == "platform" && AgentWorkspace.self_signup_enabled?
  end

  def money(cents)
    MoneyFormatter.call(cents)
  end

  def money_input_value(cents)
    amount = cents.to_i
    format("%d.%02d", amount.div(100), amount % 100)
  end

  def role_label(role)
    { "admin" => "Administrador", "reseller" => "Asesor", "coordinator" => "Coordinador" }.fetch(role, role.titleize)
  end

  def reservation_status_label(status)
    { "requested" => "Solicitada", "confirmed" => "Confirmada", "cancelled" => "Cancelada" }.fetch(status, status.humanize)
  end

  def reservation_status_class(status)
    { "requested" => "orange", "confirmed" => "green", "cancelled" => "red" }.fetch(status, "gray")
  end

  def reservation_channel_label(channel)
    { "direct" => "Directa", "reseller" => "Asesor" }.fetch(channel, channel.humanize)
  end

  def departure_status_label(status)
    { "draft" => "Borrador", "open" => "Abierta", "sold_out" => "Completa", "cancelled" => "Cancelada",
      "completed" => "Finalizada" }.fetch(status, status.humanize)
  end

  def departure_status_class(status)
    { "open" => "green", "sold_out" => "purple", "cancelled" => "red", "completed" => "gray" }.fetch(status, "gray")
  end

  def occupancy_percentage(departure)
    return 0 unless departure.capacity.to_i.positive?

    [ (departure.occupied_seats.to_f / departure.capacity * 100).round, 100 ].min
  end

  def app_icon(name, class_name: "cadence-icon", **options)
    options[:class] = class_name
    options[:aria] ||= { hidden: true }
    tag.svg(**options) { tag.use(href: "#icon-#{name}") }
  end

  def navigation_sections
    case current_role
    when "operator"
      { "Plataforma" => [ [ "Empresas y dominios", platform_companies_path, "layers" ],
        [ "Asesores", platform_agent_workspaces_path, "users" ] ] }
    when "admin"
      {
        "General" => [ [ "Inicio", dashboard_path, "grid" ], [ "Viajes", departure_offers_path, "bus" ],
          [ "Paquetes", travel_packages_path, "briefcase" ], [ "Salidas", departures_path, "calendar" ],
          [ "Reservas", reservations_path, "ticket" ] ],
        "Finanzas" => [ [ "Pagos", customer_payments_path, "credit-card" ],
          [ "Rendiciones", remittances_path, "send" ], [ "Comisiones", commissions_path, "percent" ] ],
        "Administración" => [ [ "Catálogos", catalog_path, "layers" ], [ "Equipo", team_members_path, "users" ] ]
      }
    when "reseller"
      {
        "General" => [ [ "Mi escritorio", dashboard_path, "grid" ], [ "Catálogo", departure_offers_path, "bus" ],
          [ "Mis reservas", reservations_path, "ticket" ], [ "Formularios", passenger_forms_path, "file" ] ],
        "Finanzas" => [ [ "Mis cobros", customer_payments_path, "credit-card" ],
          [ "Rendiciones", remittances_path, "send" ], [ "Comisiones", commissions_path, "percent" ] ]
      }
    else
      { "Operación" => [ [ "Hoja de ruta", departures_path, "route" ], [ "Novedades", notifications_path, "bell" ] ] }
    end
  end

  def navigation_items
    navigation_sections.values.flatten(1)
  end
end
