# Deliberately outside *_test.rb: opt-in only; no database writes or published trips.
require "prawn"
require "tmpdir"
require "open3"
abort "Use bin/gemini-smoke with a dedicated test key" unless Rails.env.test? && ENV["AGENT_GEMINI_SMOKE"] == "true" && ENV["GEMINI_SMOKE_API_KEY"].present? && ENV["GEMINI_API_KEY"] == ENV["GEMINI_SMOKE_API_KEY"]
abort "Disable E2E fixtures for a live smoke test" if ENV["AGENT_E2E_FIXTURES"] == "true"

source_class = Struct.new(:path) do
  def open(&block) = File.open(path, "rb", &block)
end
task_class = Struct.new(:source)

Dir.mktmpdir("gemini-smoke-") do |directory|
  exact = "Cordoba\nSalida 15/12/2030\nPrecio final ARS 1.250.000,50 por persona\nOrganizador: Operador Prueba\nHotel no informado."
  ambiguous = "Salta\nSalida 20 de enero (sin ano indicado)\nPrecio $450.000. Moneda y unidad no informadas. Hotel no informado."
  pdf = Prawn::Document.new { text exact }.render
  File.binwrite(File.join(directory, "single.pdf"), pdf)
  File.binwrite(File.join(directory, "multiple.pdf"), Prawn::Document.new { text exact; start_new_page; text ambiguous }.render)
  %w[jpeg png].each do |format|
    _, status = Open3.capture2e("pdftoppm", "-singlefile", "-scale-to", "1600", "-#{format}", File.join(directory, "single.pdf"), File.join(directory, "flyer"))
    abort "pdftoppm failed for #{format}" unless status.success?
  end
  # Separate ambiguous image verifies absent year/ambiguous money without a second trip's context.
  File.binwrite(File.join(directory, "ambiguous.pdf"), Prawn::Document.new { text ambiguous }.render)
  %w[flyer.jpg flyer.png single.pdf multiple.pdf ambiguous.pdf].each do |filename|
    task = task_class.new(source_class.new(File.join(directory, filename)))
    data, usage = Agent::GeminiClient.call(kind: "import", task:)
    trips = data.fetch("trips")
    expected_count = filename == "multiple.pdf" ? 2 : 1
    abort "#{filename}: expected #{expected_count} trips, got #{trips.size}" unless trips.size == expected_count
    unless filename == "ambiguous.pdf"
      trip = trips.find { |candidate| candidate["destination"].to_s.downcase.include?("cord") }
      expected = { "departs_on" => "2030-12-15", "price_cents" => 125_000_050, "currency" => "ARS", "price_unit" => "per_person", "hotel" => nil }
      abort "#{filename}: incorrect exact commercial fields" unless trip && expected.all? { |key, value| trip[key] == value }
    end
    if %w[multiple.pdf ambiguous.pdf].include?(filename)
      trip = trips.find { |candidate| candidate["destination"].to_s.downcase.include?("salta") }
      abort "#{filename}: invented ambiguous fields" unless trip && %w[departs_on currency price_unit hotel].all? { |key| trip[key].nil? }
      abort "#{filename}: incorrect Argentine thousands" unless trip["price_cents"] == 45_000_000
      abort "#{filename}: missing ambiguity warning" if trip["warnings"].empty?
    end
    abort "#{filename}: missing token usage" unless usage["totalTokenCount"].to_i.positive?
    puts "PASS #{filename}: trips=#{trips.size} model=#{Agent::GeminiClient.model} tokens=#{usage['totalTokenCount']} contract=#{Agent::AiContract::VERSION}"
  rescue Agent::GeminiClient::Failure => error
    abort "FAIL #{filename}: #{error.code} tokens=#{error.usage['totalTokenCount'] || 'unknown'} (no provider body logged)"
  end
end
