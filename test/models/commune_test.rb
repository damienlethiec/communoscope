require "test_helper"

class CommuneTest < ActiveSupport::TestCase
  test "valide avec un code INSEE, un nom et une population" do
    commune = Commune.new(code_insee: "69000", nom: "Exemple", population: 1_000)

    assert_predicate commune, :valid?
  end

  test "exige un code INSEE" do
    commune = Commune.new(nom: "Lyon", population: 522_250)

    assert_not_predicate commune, :valid?
    assert_includes commune.errors[:code_insee], "can't be blank"
  end

  test "exige un nom" do
    commune = Commune.new(code_insee: "69123", population: 522_250)

    assert_not_predicate commune, :valid?
    assert_includes commune.errors[:nom], "can't be blank"
  end

  test "refuse un code INSEE en doublon" do
    doublon = Commune.new(code_insee: communes(:lyon).code_insee, nom: "Autre", population: 1)

    assert_not_predicate doublon, :valid?
    assert_includes doublon.errors[:code_insee], "has already been taken"
  end

  test "le code INSEE est protégé par un index unique" do
    assert Commune.connection.index_exists?(:communes, :code_insee, unique: true)
  end

  test "feu retourne le dernier feu du domaine" do
    commune = communes(:lyon)
    TrafficLight.enregistrer!(commune:, domaine: "finances", couleur: "vert", justification: { "annee" => 2023 })
    dernier = TrafficLight.enregistrer!(commune:, domaine: "finances", couleur: "orange", justification: { "annee" => 2024 })

    assert_equal dernier, commune.feu("finances")
  end

  test "feu retourne nil sans feu calculé" do
    assert_nil communes(:lyon).feu("finances")
  end

  test "supprimer une commune supprime ses mesures et ses feux" do
    commune = Commune.create!(code_insee: "69999", nom: "Éphémère", population: 10)
    commune.measurements.create!(domaine: "finances", indicateur: "caf_brute", valeur: 1,
      date: Date.new(2024, 12, 31), source_url: "https://example.org")
    TrafficLight.enregistrer!(commune:, domaine: "finances", couleur: "vert", justification: { "annee" => 2024 })

    assert_difference -> { Measurement.count } => -1, -> { TrafficLight.count } => -1 do
      commune.destroy!
    end
  end
end
