require "test_helper"

class AgentDepartureDateTest < ActiveSupport::TestCase
  test "dates without a year use the current year or the next occurrence" do
    today = Date.new(2026, 11, 3)
    { "3 de febrero" => "2027-02-03", "10 de febrero" => "2027-02-10", "17 de febrero" => "2027-02-17", "24 de febrero" => "2027-02-24",
      "3 de noviembre" => "2026-11-03", "4 de noviembre" => "2026-11-04", "2 de noviembre" => "2027-11-02",
      "03/02" => "2027-02-03", "Salida: 24 de febrero" => "2027-02-24" }.each do |text, expected|
      assert_equal expected, Agent::DepartureDate.call(text:, today:), text
    end
  end

  test "explicit years are preserved even if the date is past" do
    today = Date.new(2026, 11, 3)
    assert_equal "2025-02-03", Agent::DepartureDate.call(text: "3 de febrero de 2025", today:)
    assert_equal "2025-02-03", Agent::DepartureDate.call(text: "03/02/2025", today:)
    assert_equal "2025-02-03", Agent::DepartureDate.call(value: "2025-02-03", text: "3 de febrero", today:)
  end

  test "missing days and impossible dates are not invented" do
    [ nil, "febrero", "a confirmar", "31 de febrero", "32/01" ].each do |text|
      assert_nil Agent::DepartureDate.call(text:, today: Date.new(2026, 11, 3))
    end
    assert_equal "2028-02-29", Agent::DepartureDate.call(text: "29 de febrero", today: Date.new(2027, 11, 3))
    assert_equal "2027-01-01", Agent::DepartureDate.call(text: "1 de enero", today: Date.new(2026, 12, 31))
  end
end
