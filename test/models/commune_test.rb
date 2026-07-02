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
end
