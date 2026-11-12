class Rack::Attack
  # Production and staging use the shared Redis Rails cache, across web instances.
  self.cache.store = Rails.cache

  throttle("public/ip", limit: 120, period: 1.minute) do |request|
    request.ip if request.path.start_with?("/viajes/", "/formularios/") || request.path.match?(%r{\A/[a-z0-9-]+/viajes/[^/]+/?\z})
  end

  throttle("agent-public-search/ip", limit: 60, period: 1.minute) do |request|
    request.ip if request.path.match?(%r{\A/(?:[a-z0-9-]+/)?buscar-viajes/?\z})
  end

  throttle("agent-public-images/ip", limit: 120, period: 1.minute) do |request|
    request.ip if request.path.match?(%r{\A/(?:agente|[a-z0-9-]+)/imagenes/[^/]+/[^/]+/?\z}) ||
      request.path.match?(%r{\A/[a-z0-9-]+/sobre-mi/foto/[^/]+/?\z})
  end

  throttle("agent-public-catalog/ip", limit: 120, period: 1.minute) do |request|
    request.ip if request.get? && (request.path == "/" || request.path.match?(%r{\A/[a-z0-9]+(?:-[a-z0-9]+)*/?\z}) &&
      !%w[/up /manifest /service-worker /context /dashboard /onboarding].include?(request.path))
  end

  throttle("oauth/ip", limit: 20, period: 10.minutes) do |request|
    request.ip if request.path.start_with?("/auth/")
  end

  throttle("agent-private-files/ip", limit: 120, period: 1.minute) do |request|
    request.ip if request.path.match?(%r{\A/agente/(?:viajes/[^/]+/(?:cover|source)|importaciones/[^/]+/(?:source|preview))/?\z})
  end

  throttle("agent-ai/ip", limit: 40, period: 1.minute) do |request|
    request.ip if request.post? && request.path.start_with?("/agente/importaciones", "/agente/buscador")
  end

  throttle("agent-onboarding/ip", limit: 10, period: 10.minutes) do |request|
    request.ip if request.post? && request.path == "/agente/alta"
  end

  throttle("agent-slug-suggestion/ip", limit: 60, period: 1.minute) do |request|
    request.ip if request.get? && request.path == "/agente/alta/suggestion"
  end

  self.throttled_responder = lambda do |_request|
    [ 429, { "Content-Type" => "text/plain", "Retry-After" => "60" }, [ "Demasiadas solicitudes. Intentá nuevamente en un minuto." ] ]
  end
end

Rails.application.config.middleware.use Rack::Attack
