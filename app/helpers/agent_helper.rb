module AgentHelper
  def agent_fares_for_form(revision)
    submitted = params.permit(agent_trip_revision: [ { fares: Agent::TripFares::REVIEW_FIELDS } ]).dig(:agent_trip_revision, :fares)
    fares = Agent::TripFares.review(submitted || revision.fares, defaults: revision.attributes.slice(*AgentTripRevision::FIELDS))
    legacy = if params[:agent_trip_revision]&.key?(:price)
      params.dig(:agent_trip_revision, :price)
    elsif @item&.review_data&.key?("price")
      @item.review_data["price"]
    end
    fares.first["price"] = legacy if !legacy.nil? && fares.one?
    fares
  end

  def agent_fare_amount(fare, field = "price_cents")
    return "Precio a confirmar" unless fare[field]
    ActiveSupport::NumberHelper.number_to_currency(BigDecimal(fare[field].to_s) / 100,
      unit: "#{fare['currency']} ", separator: ",", delimiter: ".", precision: 2)
  end

  def agent_public_catalog_path_with(filters = {})
    query = filters.to_h.reject { |_key, value| value.blank? }.to_query
    agent_public_catalog_filter_url + (query.present? ? "?#{query}" : "")
  end

  def agent_public_filter_label(key, value)
    case key.to_s
    when "destination", "destination_query", "q" then value
    when "month" then l(Date.iso8601("#{value}-01"), format: "%B %Y").capitalize
    when "duration" then { "4" => "Hasta 4 días", "6" => "Hasta 6 días", "7" => "7 días o más" }.fetch(value, value)
    when "price_unit" then AgentTripRevision::PRICE_UNITS.fetch(value, value)
    when "currency" then value
    else "#{agent_filter_label(key)}: #{value}"
    end
  rescue Date::Error
    value
  end

  def agent_public_price_unit(revision)
    { "per_person" => "/ persona", "per_group" => "/ grupo", "per_room" => "/ habitación" }[revision.price_unit]
  end

  def agent_trip_list_duration(revision)
    parts = []
    parts << "#{revision.duration_days} #{revision.duration_days == 1 ? 'día' : 'días'}" if revision.duration_days
    parts << "#{revision.duration_nights} #{revision.duration_nights == 1 ? 'noche' : 'noches'}" if revision.duration_nights
    parts.presence&.join(" / ") || "Sin definir"
  end

  def agent_ai_status(task)
    { "pending" => "Pendiente", "processing" => "Procesando", "completed" => "Completado", "error" => "Error" }.fetch(task.status)
  end

  def agent_ai_error(code)
    case code
    when "plan_expired" then "Tu plan venció o el espacio está suspendido. Conservamos el archivo; coordiná la reactivación con la administración de Turistack."
    when "monthly_limit" then "Agotaste el presupuesto mensual de IA. Se renueva el día 1. Podés continuar manualmente sin perder el archivo."
    when "daily_limit" then "Alcanzaste el límite diario de IA. Se renueva a medianoche de tu cuenta. Podés continuar manualmente sin perder el archivo."
    when "configuration" then "Falta configurar Gemini. Podés cargar el viaje manualmente."
    when "invalid_file" then "El archivo no pudo validarse. Probá con otra versión del documento."
    when "invalid_response", "incomplete_response" then "La IA no devolvió una ficha válida. Revisá el original o reintentá."
    else "El servicio no respondió correctamente. Podés reintentar o usar la carga y los filtros manuales."
    end
  end

  def agent_filter_label(key)
    { "destination" => "Destino", "region" => "Región", "from" => "Desde", "to" => "Hasta", "min_price" => "Precio mínimo", "max_price" => "Precio máximo", "currency" => "Moneda", "price_unit" => "Unidad", "meal_plan" => "Comidas", "transport" => "Transporte", "departure_location" => "Lugar de salida", "min_days" => "Duración mínima", "max_days" => "Duración máxima" }.fetch(key, key)
  end

  def agent_match_reasons(revision, filters)
    reasons = []
    reasons << "Destino registrado: #{revision.destination}" if filters["destination"].present?
    reasons << "Salida dentro del período solicitado: #{argentine_date(revision.departs_on)}" if filters["from"].present? || filters["to"].present?
    reasons << "Precio compatible con el presupuesto: #{agent_money(revision)}" if filters["min_price"].present? || filters["max_price"].present?
    %w[region meal_plan transport departure_location].each do |field|
      reasons << "#{agent_filter_label(field)}: #{revision.public_send(field)}" if filters[field].present?
    end
    reasons << "Duración registrada: #{revision.duration_days} días" if filters["min_days"].present? || filters["max_days"].present?
    reasons.presence || [ "Propuesta vigente de un proveedor activo." ]
  end
  def agent_price_amount(revision)
    return "Precio a confirmar" unless revision.price_cents
    ActiveSupport::NumberHelper.number_to_currency(revision.price_cents / 100.0, unit: revision.currency.to_s + " ", separator: ",", delimiter: ".", precision: 2)
  end
  def agent_money(revision)
    return "Precio a confirmar" unless revision.price_cents
    "#{agent_price_amount(revision)} · #{AgentTripRevision::PRICE_UNITS[revision.price_unit] || 'Unidad a confirmar'}"
  end
  def agent_whatsapp(revision)
    message = "Hola, quisiera consultar por #{revision.title} del #{revision.departs_on&.strftime('%d/%m/%Y')} que vi en tu página. #{agent_trip_public_url(revision.agent_trip)}"
    "https://wa.me/#{current_agent_workspace.whatsapp}?text=#{ERB::Util.url_encode(message)}"
  end
  def agent_trip_public_url(trip)
    current_agent_workspace.url(path: agent_site_trip_path(agent_slug: current_agent_workspace.slug, slug: trip.slug))
  end

  def agent_catalog_public_url
    current_agent_workspace.url
  end

  def agent_public_search_path_for_workspace
    if request.host == PlatformHosts.platform_host
      agent_site_search_path(agent_slug: current_agent_workspace.slug)
    else
      agent_public_search_path
    end
  end

  def agent_public_catalog_filter_url
    controller_path == "agent/website" ? preview_agent_website_path : request.path
  end

  def agent_about_photo_public_url
    if request.host == current_agent_workspace.hostname
      return PlatformHosts.url(host: request.host, path: agent_public_about_photo_path(blob_id: current_agent_workspace.about_photo.blob_id))
    end
    current_agent_workspace.url(path: agent_site_about_photo_path(agent_slug: current_agent_workspace.slug, blob_id: current_agent_workspace.about_photo.blob_id))
  end

  def agent_image_public_url(trip, revision)
    if request.host == current_agent_workspace.hostname
      return PlatformHosts.url(host: request.host, path: agent_public_image_path(slug: trip.slug, revision_id: revision.id))
    end
    current_agent_workspace.url(path: agent_site_image_path(agent_slug: current_agent_workspace.slug, slug: trip.slug, revision_id: revision.id))
  end

  def agent_share_text(trip)
    revision = trip.published_revision
    "Conocé todos los detalles de este viaje a #{revision.destination}:\n\n#{agent_trip_public_url(trip)}"
  end

  def agent_status(trip)
    return "Vencido" if trip.expired?
    return "Proveedor pausado" if trip.status == "published" && trip.current_revision&.agent_supplier&.status == "paused"
    { "draft" => "Borrador", "published" => "Publicado", "unpublished" => "Despublicado", "archived" => "Archivado" }.fetch(trip.status)
  end
end
