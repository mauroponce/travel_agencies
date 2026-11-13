require "test_helper"
require_relative "../support_agent_data"

class AgentDepartureDateTest < ActiveSupport::TestCase
  include AgentTestData

  test "November 12 infers years from months and original evidence regardless of model year" do
    today = Date.new(2026, 11, 12)
    [ 2, 8, 11, 14, 17, 25 ].each do |day|
      assert_equal "2026-11-#{day.to_s.rjust(2, '0')}", Agent::DepartureDate.call(text: "#{day} de noviembre", value: "2027-11-#{day.to_s.rjust(2, '0')}", today:)
    end
    assert_equal "2027-02-11", Agent::DepartureDate.call(text: "11 de febrero", today:)
    assert_equal "2026-12-20", Agent::DepartureDate.call(text: "20/12", today:)
    assert_equal "2024-11-02", Agent::DepartureDate.call(text: "2 de noviembre de 2024", value: "2026-11-02", today:)
    assert_equal "2024-11-02", Agent::DepartureDate.call(value: "2024-11-02", today:)
    assert_equal "2027-02-24", Agent::DepartureDate.call(text: "Salida: 24 de febrero", today:)
    assert_equal "2025-02-03", Agent::DepartureDate.call(text: "03/02/2025", today:)
  end

  test "month boundaries leap years and invalid evidence are deterministic" do
    assert_equal "2027-01-01", Agent::DepartureDate.call(text: "1 de enero", today: Date.new(2026, 12, 31))
    assert_equal "2027-01-01", Agent::DepartureDate.call(text: "1 de enero", today: Date.new(2027, 1, 31))
    assert_equal "2028-02-29", Agent::DepartureDate.call(text: "29 de febrero", today: Date.new(2027, 11, 12))
    assert_nil Agent::DepartureDate.call(text: "29 de febrero", today: Date.new(2026, 11, 12))
    assert_nil Agent::DepartureDate.call(text: "31/11", today: Date.new(2026, 11, 12))
    assert_nil Agent::DepartureDate.call(text: "noviembre", value: "2026-11-02", today: Date.new(2026, 11, 12))
    assert_nil Agent::DepartureDate.call(value: "2026-02-30")
    [ nil, "febrero", "a confirmar", "31 de febrero", "32/01" ].each do |text|
      assert_nil Agent::DepartureDate.call(text:, today: Date.new(2026, 11, 12))
    end
  end

  test "Gemini uses workspace local month at UTC month boundary" do
    workspace = agent_workspace(timezone: "America/Argentina/Buenos_Aires")
    travel_to Time.utc(2026, 12, 1, 1)
    task = workspace.agent_imports.new
    reference = Agent::GeminiClient.reference_date(task)
    assert_equal Date.new(2026, 11, 30), reference
    assert_equal "2026-11-02", Agent::DepartureDate.call(text: "2 de noviembre", today: reference)
    assert_equal "2027-02-11", Agent::DepartureDate.call(text: "11 de febrero", today: reference)
  end

  test "grouped day lists expand without inventing days for month-only or travel ranges" do
    assert_equal [ "22 de febrero", "27 de febrero", "11 de marzo" ], Agent::DepartureDate.labels("22-27 de febrero y 11 de marzo")
    assert_equal [ "7 de marzo", "14 de marzo", "11 de abril", "18 de abril" ], Agent::DepartureDate.labels("7-14 de marzo y 11-18 de abril")
    assert_equal [ "2 de noviembre", "8 de noviembre", "11 de noviembre" ], Agent::DepartureDate.labels("2, 8 y 11 de noviembre")
    assert_equal [ "marzo-abril" ], Agent::DepartureDate.labels("marzo-abril")
    assert_equal [ "del 7 al 14 de marzo" ], Agent::DepartureDate.labels("del 7 al 14 de marzo")
  end
end
