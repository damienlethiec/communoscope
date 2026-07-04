require "test_helper"

class TrafficLightTest < ActiveSupport::TestCase
  setup do
    @attributs = {
      commune: communes(:lyon),
      domaine: "finances",
      couleur: "vert",
      justification: { "annee" => 2024, "indicateurs" => [] },
      date: Date.new(2026, 7, 4)
    }
  end

  test "valide avec tous ses attributs" do
    assert_predicate TrafficLight.new(@attributs), :valid?
  end

  %i[domaine couleur justification date].each do |attribut|
    test "exige #{attribut}" do
      traffic_light = TrafficLight.new(@attributs.except(attribut))

      assert_not_predicate traffic_light, :valid?
      assert_predicate traffic_light.errors[attribut], :any?
    end
  end

  test "refuse une couleur inconnue" do
    traffic_light = TrafficLight.new(@attributs.merge(couleur: "violet"))

    assert_not_predicate traffic_light, :valid?
    assert_predicate traffic_light.errors[:couleur], :any?
  end

  test "enregistrer! crée la première ligne" do
    assert_difference -> { TrafficLight.count }, 1 do
      TrafficLight.enregistrer!(**@attributs)
    end
  end

  test "enregistrer! n'ajoute pas de ligne quand rien ne change" do
    TrafficLight.enregistrer!(**@attributs)

    assert_no_difference -> { TrafficLight.count } do
      TrafficLight.enregistrer!(**@attributs)
    end
  end

  test "enregistrer! ignore les différences symboles/chaînes dans la justification" do
    TrafficLight.enregistrer!(**@attributs)

    assert_no_difference -> { TrafficLight.count } do
      TrafficLight.enregistrer!(**@attributs.merge(justification: { annee: 2024, indicateurs: [] }))
    end
  end

  test "enregistrer! ajoute exactement une ligne quand la couleur change" do
    TrafficLight.enregistrer!(**@attributs)

    assert_difference -> { TrafficLight.count }, 1 do
      TrafficLight.enregistrer!(**@attributs.merge(couleur: "orange"))
    end
  end

  test "enregistrer! ajoute une ligne quand la justification change à couleur constante" do
    TrafficLight.enregistrer!(**@attributs)

    assert_difference -> { TrafficLight.count }, 1 do
      TrafficLight.enregistrer!(**@attributs.merge(justification: { "annee" => 2025, "indicateurs" => [] }))
    end
  end

  test "enregistrer! historise par commune × domaine sans écraser l'existant" do
    premier = TrafficLight.enregistrer!(**@attributs)
    second = TrafficLight.enregistrer!(**@attributs.merge(couleur: "rouge"))

    assert_not_equal premier.id, second.id
    assert_equal %w[vert rouge], TrafficLight.where(commune: communes(:lyon), domaine: "finances").order(:id).pluck(:couleur)
  end

  test "enregistrer! distingue les domaines" do
    TrafficLight.enregistrer!(**@attributs)

    assert_difference -> { TrafficLight.count }, 1 do
      TrafficLight.enregistrer!(**@attributs.merge(domaine: "eau"))
    end
  end

  test "dernier retourne la ligne la plus récente pour une commune et un domaine" do
    TrafficLight.enregistrer!(**@attributs)
    dernier = TrafficLight.enregistrer!(**@attributs.merge(couleur: "orange"))

    assert_equal dernier, TrafficLight.dernier(commune: communes(:lyon), domaine: "finances")
    assert_nil TrafficLight.dernier(commune: communes(:villeurbanne), domaine: "finances")
  end
end
