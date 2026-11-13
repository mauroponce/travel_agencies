require "test_helper"

class SpanishRoutesTest < ActionDispatch::IntegrationTest
  test "new and edit pages use Spanish paths across the application" do
    assert_routing "/asesor/viajes/nuevo", controller: "agent/trips", action: "new"
    assert_routing "/asesor/viajes/viaje/editar", controller: "agent/trips", action: "edit", id: "viaje"
    assert_routing "/salidas/nuevo", controller: "departures", action: "new"
    assert_routing "/ofertas/oferta/editar", controller: "departure_offers", action: "edit", id: "oferta"
    assert_routing "/plataforma/empresas/nuevo", controller: "platform/companies", action: "new"
    assert_routing "/plataforma/asesores/nuevo", controller: "platform/agent_workspaces", action: "new"
  end

  test "trip actions and import review use Spanish paths" do
    assert_routing({ method: "post", path: "/asesor/viajes/viaje/publicar" }, controller: "agent/trips", action: "publish", id: "viaje")
    assert_routing({ method: "post", path: "/asesor/viajes/viaje/despublicar" }, controller: "agent/trips", action: "unpublish", id: "viaje")
    assert_routing "/asesor/viajes/comparar", controller: "agent/trips", action: "compare"
    assert_routing "/asesor/mi-web/vista-previa", controller: "agent/website", action: "preview"
    assert_routing "/asesor/viajes/importaciones/importacion", controller: "agent/trip_imports", action: "show", id: "importacion", format: :json
    assert_routing({ method: "post", path: "/asesor/viajes/importaciones/importacion/reintentar" }, controller: "agent/trip_imports", action: "retry_processing", id: "importacion", format: :json)
    assert_equal "/asesor/exportar.json", agent_export_path(format: :json)
  end

  test "navigation authentication and operations use Spanish paths" do
    assert_routing "/panel", controller: "dashboard", action: "show"
    assert_routing "/contexto", controller: "contexts", action: "show"
    assert_routing "/alta", controller: "onboardings", action: "show"
    assert_routing({ method: "post", path: "/autenticacion/iniciar" }, controller: "authentication", action: "start")
    assert_routing "/autenticacion/continuar", controller: "authentication", action: "continue"
    assert_routing "/autenticacion/intercambiar", controller: "authentication", action: "exchange"
    assert_routing({ method: "delete", path: "/sesion" }, controller: "sessions", action: "destroy")
    assert_routing "/salidas/salida/operacion", controller: "departures", action: "operation", id: "salida"
    assert_routing({ method: "post", path: "/salidas/salida/embarques/sincronizar" }, controller: "boarding_events", action: "sync", departure_id: "salida")
    assert_equal "/viajes/oferta/estado", public_trip_status_path(offer_slug: "oferta")
  end
end
