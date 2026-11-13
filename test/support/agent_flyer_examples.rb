module AgentFlyerExamples
  def self.fare(price:, basis: nil, list_price: nil, hotel: nil)
    Agent::AiContract.fare_properties.keys.index_with { nil }.merge(
      "label" => basis, "price_basis" => basis, "price_cents" => price,
      "list_price_cents" => list_price, "hotel" => hotel, "price_unit" => "per_person")
  end

  def self.program(title:, dates:, fares:, **attributes)
    Agent::AiContract.trip_properties.keys.index_with { nil }.merge(
      "title" => title, "destination" => title, "supplier_name" => "Operadora de viajes",
      "departures" => dates.map { |label| { "label" => label, "departs_on" => nil, "returns_on" => nil } },
      "fares" => fares, "price_unit" => "per_person", "warnings" => [], "evidence" => []).merge(attributes.stringify_keys)
  end

  def self.multiple_bases
    [ program(title: "Villa Carlos Paz", supplier_name: "Carlos Sansot", dates: [ 2, 8, 11, 14, 17, 25 ].map { |day| "#{day} de noviembre" },
      fares: [ fare(price: 10_500_000, basis: "Base triple / cuádruple", list_price: 13_125_000), fare(price: 11_500_000, basis: "Base doble", list_price: 14_375_000) ],
      duration_days: 5, duration_nights: 3, hotel: "Gran Victoria", meal_plan: "Media pensión", transport: "Bus semi cama",
      included_services: "Coordinador", conditions: "Contado/efectivo. Gastos administrativos: $15.000 adicionales.") ]
  end

  def self.multiple_programs
    programs = [
      program(title: "Mina Clavero", dates: [ "21 de febrero" ], fares: [ fare(price: 1_199_900) ], duration_nights: 3, hotel: "Hotel Mina Clavero", meal_plan: "Pensión completa"),
      program(title: "Carlos Paz", dates: [ "13 de febrero" ], fares: [ fare(price: 1_499_900, hotel: "Hotel Grand Prix"), fare(price: 1_299_900, hotel: "Hotel Sierrasol") ], duration_nights: 3, meal_plan: "Media pensión"),
      program(title: "Mar del Plata", dates: [ "17 de febrero" ], fares: [ fare(price: 1_999_900) ], duration_nights: 5, hotel: "Hotel Flamingo", meal_plan: "Pensión completa"),
      program(title: "Mar del Plata", dates: [ "22 de febrero", "27 de febrero", "11 de marzo" ], fares: [ fare(price: 1_899_900) ], duration_nights: 5, hotel: "Hotel Flamingo", meal_plan: "Pensión completa"),
      program(title: "Perlas de La Rioja, San Juan y Catamarca", dates: [ "marzo-abril" ], fares: [ fare(price: 1_749_900) ], duration_nights: 4, meal_plan: "Media pensión", included_services: "Excursiones incluidas"),
      program(title: "Joyas de Ruta 40", dates: [ "6 de marzo" ], fares: [ fare(price: 3_999_000) ], duration_nights: 8, hotel: "Hoteles de categoría", meal_plan: "Media pensión"),
      program(title: "Patagonia soñada", dates: [ "7 de marzo", "14 de marzo", "11 de abril", "18 de abril" ], fares: [ fare(price: 5_999_000) ], duration_nights: 12, hotel: "Hoteles de categoría", meal_plan: "Media pensión")
    ]
    programs.each { |entry| entry["supplier_name"] = "GrupoRolSol"; entry["conditions"] = "Promoción hasta el 31 de enero o agotar stock. Asistencia COVID-19 incluida." }
    programs
  end
end
