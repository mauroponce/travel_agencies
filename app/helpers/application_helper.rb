module ApplicationHelper
  def money(cents)
    MoneyFormatter.call(cents)
  end

  def money_input_value(cents)
    amount = cents.to_i
    format("%d.%02d", amount.div(100), amount % 100)
  end

  def role_label(role)
    { "admin" => "Administrador", "reseller" => "Revendedor", "coordinator" => "Coordinador" }.fetch(role, role.titleize)
  end

  def navigation_items
    case current_role
    when "admin"
      [ [ "Resumen", dashboard_path, "▦" ], [ "Viajes", departure_offers_path, "🚌" ], [ "Paquetes", travel_packages_path, "🗺" ],
       [ "Salidas", departures_path, "📅" ], [ "Reservas", reservations_path, "🎟" ], [ "Pagos", customer_payments_path, "💳" ],
       [ "Rendiciones", remittances_path, "◫" ], [ "Comisiones", commissions_path, "%" ], [ "Catálogos", catalog_path, "▤" ],
       [ "Equipo", team_members_path, "👥" ] ]
    when "reseller"
      [ [ "Mi escritorio", dashboard_path, "▦" ], [ "Catálogo", departure_offers_path, "🚌" ], [ "Mis reservas", reservations_path, "🎟" ],
       [ "Formularios", passenger_forms_path, "📄" ], [ "Mis cobros", customer_payments_path, "💳" ], [ "Rendiciones", remittances_path, "◫" ],
       [ "Comisiones", commissions_path, "%" ] ]
    else
      [ [ "Hoja de ruta", departures_path, "↝" ], [ "Novedades", notifications_path, "🔔" ] ]
    end
  end
end
