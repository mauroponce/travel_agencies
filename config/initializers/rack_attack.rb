class Rack::Attack
  throttle("public/ip", limit: 120, period: 1.minute) do |request|
    request.ip if request.path.start_with?("/viajes/", "/formularios/")
  end

  throttle("oauth/ip", limit: 20, period: 10.minutes) do |request|
    request.ip if request.path.start_with?("/auth/")
  end

  throttle("agent-ai/ip", limit: 40, period: 1.minute) do |request|
    request.ip if request.post? && request.path.start_with?("/agente/importaciones", "/agente/buscador")
  end

  throttle("agent-onboarding/ip", limit: 10, period: 10.minutes) do |request|
    request.ip if request.post? && request.path == "/agente/alta"
  end

  self.throttled_responder = lambda do |_request|
    [ 429, { "Content-Type" => "text/plain", "Retry-After" => "60" }, [ "Demasiadas solicitudes. Intentá nuevamente en un minuto." ] ]
  end
end

Rails.application.config.middleware.use Rack::Attack
