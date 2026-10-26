module AgentHelper
  def agent_ai_status(task)
    { "pending" => "Pendiente", "processing" => "Procesando", "completed" => "Completado", "error" => "Error" }.fetch(task.status)
  end

  def agent_ai_error(code)
    case code
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
    reasons << "Salida dentro del período solicitado: #{revision.departs_on}" if filters["from"].present? || filters["to"].present?
    reasons << "Precio compatible con el presupuesto: #{agent_money(revision)}" if filters["min_price"].present? || filters["max_price"].present?
    %w[region meal_plan transport departure_location].each do |field|
      reasons << "#{agent_filter_label(field)}: #{revision.public_send(field)}" if filters[field].present?
    end
    reasons << "Duración registrada: #{revision.duration_days} días" if filters["min_days"].present? || filters["max_days"].present?
    reasons.presence || [ "Propuesta vigente de un proveedor activo." ]
  end
  def agent_money(revision)
    return "Precio a confirmar" unless revision.price_cents
    amount = ActiveSupport::NumberHelper.number_to_currency(revision.price_cents / 100.0, unit: revision.currency.to_s + " ", separator: ",", delimiter: ".", precision: 2)
    "#{amount} · #{AgentTripRevision::PRICE_UNITS[revision.price_unit] || 'Unidad a confirmar'}"
  end
  def agent_whatsapp(revision)
    message = "Hola, quisiera consultar por #{revision.title} del #{revision.departs_on&.strftime('%d/%m/%Y')} que vi en tu página. #{agent_trip_public_url(revision.agent_trip)}"
    "https://wa.me/#{current_agent_workspace.whatsapp}?text=#{ERB::Util.url_encode(message)}"
  end
  def agent_trip_public_url(trip)
    current_agent_workspace.url(path: agent_public_trip_path(slug: trip.slug))
  end

  def agent_share_text(trip)
    revision = trip.published_revision
    "Conocé todos los detalles de este viaje a #{revision.destination}:\n\n#{agent_trip_public_url(trip)}"
  end

  def agent_status(trip)
    return "Vencido" if trip.expired?
    { "draft" => "Borrador", "published" => "Publicado", "unpublished" => "Despublicado", "archived" => "Archivado" }.fetch(trip.status)
  end
end
