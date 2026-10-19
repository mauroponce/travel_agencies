class MoneyFormatter
  def self.call(cents)
    ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0, unit: "$", separator: ",", delimiter: ".", precision: 2)
  end
end
