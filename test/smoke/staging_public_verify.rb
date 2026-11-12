# Exercise anonymous HTTP through the same forwarded-HTTPS configuration as Caddy.
require "net/http"
require "nokogiri"
abort "not disposable staging" unless Rails.env.staging? && PlatformHosts.base_domain == "smoke.example.test"
trip = AgentTrip.find_by!(slug: "smoke-public")
workspace = trip.agent_workspace
routes = Rails.application.routes.url_helpers
canonical_path = routes.agent_site_trip_path(agent_slug: workspace.slug, slug: trip.slug)
canonical = PlatformHosts.url(host: PlatformHosts.platform_host, path: canonical_path)
abort "HTTPS required" unless canonical.start_with?("https://")
fetch = lambda do |host, path|
  Net::HTTP.start("127.0.0.1", 3000) do |http|
    http.get(path, "Host" => host, "X-Forwarded-Proto" => "https")
  end
end
%w[/test/sign-in /test/pro-lifecycle/prepare /test/pro-lifecycle].each do |path|
  abort "test fixture exposed in staging" unless fetch.call(PlatformHosts.platform_host, path).code == "404"
end
[ [ PlatformHosts.platform_host, canonical_path ], [ workspace.hostname, "/viajes/#{trip.slug}" ] ].each do |host, path|
  original = fetch.call(host, routes.source_agent_trip_path(trip))
  abort "private PDF exposed" unless original.code == "302" && !original.body.b.start_with?("%PDF".b)
  page = fetch.call(host, path)
  if ENV["SMOKE_UNPUBLISHED"] == "true"
    abort "unpublished trip exposed" unless page.code == "404"
    image_path = host == workspace.hostname ? routes.agent_public_image_path(slug: trip.slug, revision_id: trip.published_revision_id) : routes.agent_site_image_path(agent_slug: workspace.slug, slug: trip.slug, revision_id: trip.published_revision_id)
    abort "unpublished image exposed" unless fetch.call(host, image_path).code == "404"
    next
  end
  abort "public page unavailable" unless page.code == "200"
  html = Nokogiri::HTML(page.body)
  abort "missing public title" unless html.text.include?("Oferta smoke")
  abort "invalid HTTPS canonical" unless html.at_css('link[rel="canonical"]')&.[]("href") == canonical
  abort "inconsistent og:url" unless html.at_css('meta[property="og:url"]')&.[]("content") == canonical
  image = URI.parse(html.at_css('meta[property="og:image"]')&.[]("content").to_s)
  abort "invalid image origin" unless image.scheme == "https" && image.host == host
  jpeg = fetch.call(image.host, image.request_uri)
  abort "public JPEG unavailable" unless jpeg.code == "200" && jpeg["Content-Type"].start_with?("image/jpeg") && jpeg.body.b.start_with?("\xFF\xD8\xFF".b)
  %w[PRIVATE-SMOKE-NOTE PRIVATE-SMOKE-CLIENT PRIVATE-SMOKE-EMAIL].each do |secret|
    abort "private contact exposed" if page.body.include?(secret)
  end
  abort "private supplier exposed" if page.body.include?("PRIVATE SMOKE NOTES")
end
puts "Canonical HTTPS, Open Graph, legacy host and image visibility: OK"
