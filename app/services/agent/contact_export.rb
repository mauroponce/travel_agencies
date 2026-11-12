require "csv"

module Agent
  class ContactExport
    def self.call(workspace:, notes: false)
      CSV.generate(force_quotes: true) do |csv|
        csv << (notes ? %w[Cliente Teléfono Email Fecha Nota Viaje] : %w[Nombre Teléfono Email Archivado])
        workspace.agent_clients.includes(:notes).find_each do |client|
          if notes
            client.notes.order(:created_at, :id).each do |note|
              csv << [ client.name, client.phone, client.email, note.created_at.iso8601, note.body, note.agent_trip_id ].map { |value| cell(value) }
            end
          else
            csv << [ client.name, client.phone, client.email, client.archived_at&.iso8601 ].map { |value| cell(value) }
          end
        end
      end
    end

    # Quotes alone do not prevent spreadsheet formula execution.
    def self.cell(value)
      text = value.to_s
      text.match?(/\A[[:space:]]*[=+@\-]/) || text.start_with?("\t", "\r", "\n") ? "'#{text}" : text
    end
  end
end
