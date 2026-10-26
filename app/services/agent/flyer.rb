require "timeout"
require "tmpdir"

module Agent
  # Original bytes are never transformed for images. PDFs keep their source and
  # get a separate first-page JPEG. No signed/global Active Storage URL is used.
  class Flyer
    def self.prepare_import!(task)
      return if task.preview.attached?
      task.source.open do |file|
        mime = UploadValidator.call(file)
        if mime == "application/pdf"
          render_pdf(file.path) { |image| task.preview.attach(upload_image(image)) }
        else
          task.preview.attach(task.source.blob)
        end
      end
    end

    def self.attach!(revision:, upload: nil, source_import: nil, previous: nil)
      if upload.present?
        if upload.is_a?(ActiveStorage::Blob)
          upload.open do |file|
            mime = UploadValidator.call(file)
            revision.flyer_source.attach(upload)
            if mime == "application/pdf"
              render_pdf(file.path) { |image| revision.cover.attach(upload_image(image)) }
            else
              revision.cover.attach(upload)
            end
          end
        else
          mime = UploadValidator.call(upload)
          revision.flyer_source.attach(upload)
          if mime == "application/pdf"
            render_pdf(upload.tempfile.path) { |image| revision.cover.attach(upload_image(image)) }
          else
            revision.cover.attach(revision.flyer_source.blob)
          end
        end
      elsif source_import&.source&.attached?
        prepare_import!(source_import)
        revision.flyer_source.attach(source_import.source.blob)
        revision.cover.attach(source_import.preview.blob)
      elsif previous
        revision.flyer_source.attach(previous.flyer_source.blob) if previous.flyer_source.attached?
        revision.cover.attach(previous.cover.blob) if previous.cover.attached?
      end
    end

    def self.upload_image(image)
      ActiveStorage::Blob.create_and_upload!(io: image, filename: "flyer.jpg", content_type: "image/jpeg")
    end

    def self.render_pdf(path)
      Dir.mktmpdir("turistack-flyer-") do |directory|
        prefix = File.join(directory, "first-page")
        pid = Process.spawn("pdftoppm", "-f", "1", "-l", "1", "-singlefile", "-scale-to", "1600", "-jpeg", "-jpegopt", "quality=90", path, prefix,
          out: File::NULL, err: File::NULL, pgroup: true, rlimit_cpu: 12, rlimit_as: 512.megabytes, rlimit_fsize: 12.megabytes)
        begin
          _, status = Timeout.timeout(15) { Process.wait2(pid) }
          raise UploadValidator::Invalid, "No pudimos convertir el PDF. Probá subir una imagen JPG o PNG." unless status.success?
        rescue Timeout::Error
          Process.kill("KILL", -pid) rescue Errno::ESRCH
          Process.wait(pid) rescue Errno::ECHILD
          raise UploadValidator::Invalid, "El PDF tarda demasiado en convertirse. Probá subir una imagen."
        end
        File.open("#{prefix}.jpg", "rb") do |image|
          UploadValidator.call(image, images_only: true)
          yield image
        end
      end
    rescue Errno::ENOENT
      raise UploadValidator::Invalid, "No está disponible la conversión de PDF. Podés subir un JPG o PNG."
    end
  end
end
