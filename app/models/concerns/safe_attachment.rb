module SafeAttachment
  extend ActiveSupport::Concern

  ALLOWED_DOCUMENT_TYPES = %w[application/pdf image/jpeg image/png image/webp].freeze
  MAX_DOCUMENT_SIZE = 10.megabytes

  private

  def validate_safe_attachment(name)
    attachment = public_send(name)
    return unless attachment.attached?
    blobs = attachment.respond_to?(:blobs) ? attachment.blobs : [ attachment.blob ]
    blobs.each do |blob|
      errors.add(name, "supera el límite de 10 MB") if blob.byte_size > MAX_DOCUMENT_SIZE
      errors.add(name, "debe ser PDF, JPEG, PNG o WebP") unless ALLOWED_DOCUMENT_TYPES.include?(blob.content_type)
    end
  end
end
