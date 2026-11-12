module Agent
  class ClientDirectory
    # Substring search cannot use nondeterministic ciphertext. Decrypt only the
    # owner's scoped directory, in batches; neither terms nor PII enter SQL.
    # Retain only sort keys/IDs, then paginate the scoped relation as usual.
    def self.call(scope:, query: nil)
      term = query.presence.to_s.first(200).downcase
      matches = []
      scope.find_each(batch_size: 100) do |client|
        values = [ client.name, client.phone, client.email ].map { |value| value.to_s.downcase }
        matches << [ values.first, client.id ] if term.empty? || values.any? { |value| value.include?(term) }
      end
      ids = matches.sort.map(&:last)
      scope.in_order_of(:id, ids)
    end
  end
end
