require "test_helper"

class AgentRateLimitTest < ActiveSupport::TestCase
  setup do
    travel_to Time.current.change(sec: 10)
    @previous_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    @middleware = Rack::Attack.new(->(_env) { [ 200, { "content-type" => "text/plain" }, [ "OK" ] ] })
  end

  teardown do
    Rack::Attack.reset!
    Rack::Attack.cache.store = @previous_store
    travel_back
  end

  def request_status(path, method: "GET")
    @middleware.call(Rack::MockRequest.env_for("http://#{PlatformHosts.platform_host}#{path}", method:, "REMOTE_ADDR" => "127.0.0.1")).first
  end

  test "canonical trips search images and signup are actually throttled while assets are excluded" do
    {
      "/asesor/viajes/viaje-canonico" => 120,
      "/asesor/buscar-viajes" => 60,
      "/asesor/imagenes/viaje/revision" => 120,
      "/asesor/sobre-mi/foto/blob" => 120,
      "/buscar-viajes" => 60,
      "/agente/imagenes/viaje/revision" => 120,
      "/agente/alta/suggestion" => 60
    }.each do |path, limit|
      Rack::Attack.reset!
      limit.times { assert_equal 200, request_status(path), path }
      assert_equal 429, request_status(path), "Missing throttle for #{path}"
    end
    Rack::Attack.reset!
    130.times { assert_equal 200, request_status("/assets/example.css") }
    10.times { assert_equal 200, request_status("/agente/alta", method: "POST") }
    assert_equal 429, request_status("/agente/alta", method: "POST")
  end
end
