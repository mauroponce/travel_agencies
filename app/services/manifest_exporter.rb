require "csv"

class ManifestExporter
  def self.csv(passengers)
    CSV.generate(col_sep: ";", write_headers: true, headers: [ "Pasajero", "Documento", "Parada", "Hotel", "Estado" ]) do |csv|
      passengers.each { |p| csv << [ p.full_name, p.masked_document, p.departure_stop.published_name, p.accommodation.name, p.boarding_status ] }
    end
  end

  def self.pdf(departure, passengers)
    Prawn::Document.new do |pdf|
      pdf.text "Turistack · Manifiesto #{departure.code}", size: 18, style: :bold
      pdf.text I18n.l(departure.departs_at, format: :long)
      pdf.move_down 16
      passengers.each { |p| pdf.text "#{p.full_name} · #{p.masked_document} · #{p.departure_stop.published_name} · #{p.accommodation.name}" }
    end.render
  end
end
