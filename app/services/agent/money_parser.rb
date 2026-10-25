module Agent
  # The reseller form accepts Argentine thousands even without a decimal comma.
  # Preserve the agency parser's existing decimal contract.
  class MoneyParser < ::MoneyParser
    def self.call(value)
      amount = value.to_s.strip.delete("$\u00A0 ")
      amount = amount.delete(".") if amount.match?(/\A[+-]?\d{1,3}(?:\.\d{3})+\z/)
      super(amount)
    end
  end
end
