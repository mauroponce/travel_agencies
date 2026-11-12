require "pdf/reader"
require "timeout"

module Agent
  class UploadValidator
    class Invalid < StandardError; end
    TYPES = %w[image/jpeg image/png image/webp application/pdf].freeze
    def self.max_pdf_pages = Integer(ENV.fetch("AGENT_MAX_PDF_PAGES", "10")).clamp(1, 20)
    def self.consumption_units(upload)
      mime = call(upload)
      return 1 unless mime == "application/pdf"
      io = upload.respond_to?(:tempfile) ? upload.tempfile : upload
      PDF::Reader.new(io).page_count
    ensure
      io.rewind if io.respond_to?(:rewind)
    end
    def self.call(upload, images_only: false)
      io = upload.respond_to?(:tempfile) ? upload.tempfile : upload
      raise Invalid, "Seleccioná un archivo válido." unless io.respond_to?(:rewind) && io.respond_to?(:read)
      raise Invalid, "El archivo supera los 10 MB o está vacío." unless io.size.between?(1, 10.megabytes)
      io.rewind
      mime = Marcel::MimeType.for(io)
      io.rewind
      allowed = images_only ? TYPES - [ "application/pdf" ] : TYPES
      unless allowed.include?(mime)
        raise Invalid, images_only ? "Usá una imagen JPG, PNG o WebP válida." : "Usá un archivo JPG, PNG, WebP o PDF válido."
      end
      if upload.respond_to?(:content_type) && upload.content_type != mime
        raise Invalid, "El contenido del archivo no coincide con el tipo declarado."
      end
      if mime == "application/pdf"
        Timeout.timeout(8, Invalid, "El PDF es demasiado complejo. Usá un documento más pequeño.") do
          reader = PDF::Reader.new(io)
          raise Invalid, "El PDF debe tener entre 1 y #{max_pdf_pages} páginas." unless reader.page_count.between?(1, max_pdf_pages)
          # Parse each page so corrupt/encrypted input fails before reaching Gemini.
          reader.pages.each { |page| page.text }
        end
      else
        header = io.read(32)
        valid = case mime
        when "image/png" then header.bytesize >= 24 && header[12, 4] == "IHDR" && header[16, 8].unpack("NN").all? { |dimension| dimension.between?(1, 16000) }
        when "image/jpeg" then header.start_with?("\xFF\xD8\xFF".b) && io.size > 32
        when "image/webp" then header[0, 4] == "RIFF" && header[8, 4] == "WEBP" && [ "VP8 ", "VP8L", "VP8X" ].include?(header[12, 4])
        end
        raise Invalid, "La imagen no es válida." unless valid
      end
      io.rewind
      mime
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError, PDF::Reader::EncryptedPDFError, EOFError, Zlib::Error
      raise Invalid, "El PDF está dañado, cifrado o no es compatible."
    ensure
      io.rewind if io.respond_to?(:rewind)
    end
  end
end
