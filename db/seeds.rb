# Communes de la Métropole de Lyon (EPCI 200046977), exportées depuis
# https://geo.api.gouv.fr/epcis/200046977/communes?fields=code,nom,population
# et versionnées dans db/seeds/communes_metropole_lyon.json. Idempotent.
communes = JSON.parse(Rails.root.join("db/seeds/communes_metropole_lyon.json").read)

communes.each do |attributes|
  commune = Commune.find_or_initialize_by(code_insee: attributes.fetch("code"))
  commune.update!(nom: attributes.fetch("nom"), population: attributes.fetch("population"))
end
