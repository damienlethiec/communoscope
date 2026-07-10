require "test_helper"

class MeasurementTest < ActiveSupport::TestCase
  setup do
    @attributs = {
      commune: communes(:lyon),
      domaine: "finances",
      indicateur: "dette_par_habitant",
      valeur: 604.06,
      date: Date.new(2024, 12, 31),
      source_url: "https://www.data.gouv.fr/datasets/comptes-individuels-des-communes-fichier-global-2023-2024"
    }
  end

  test "valide avec tous ses attributs" do
    assert_predicate Measurement.new(@attributs), :valid?
  end

  %i[domaine indicateur valeur date source_url].each do |attribut|
    test "exige #{attribut}" do
      measurement = Measurement.new(@attributs.except(attribut))

      assert_not_predicate measurement, :valid?
      assert_predicate measurement.errors[attribut], :any?
    end
  end

  test "exige une commune" do
    measurement = Measurement.new(@attributs.except(:commune))

    assert_not_predicate measurement, :valid?
  end

  test "refuse un doublon commune × domaine × indicateur × date" do
    Measurement.create!(@attributs)
    doublon = Measurement.new(@attributs.merge(valeur: 999))

    assert_not_predicate doublon, :valid?
    assert_predicate doublon.errors[:indicateur], :any?
  end

  test "accepte la même mesure à une autre date" do
    Measurement.create!(@attributs)

    assert_predicate Measurement.new(@attributs.merge(date: Date.new(2023, 12, 31))), :valid?
  end

  test "l'unicité est protégée par un index unique en base" do
    assert Measurement.connection.index_exists?(
      :measurements, [ :commune_id, :domaine, :indicateur, :date ], unique: true
    )
  end
end
