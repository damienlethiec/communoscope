require "test_helper"

class CommunesControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Lyon porte un feu calculé ; Villeurbanne n'en a aucun (état neutre).
    TrafficLight.enregistrer!(
      commune: communes(:lyon),
      domaine: "finances",
      couleur: "orange",
      justification: {
        "annee" => 2023,
        "source_url" => "https://data.economie.gouv.fr",
        "indicateurs" => [
          { "indicateur" => "endettement", "libelle" => "Endettement", "couleur" => "orange", "annee" => 2023 },
          { "indicateur" => "autofinancement", "libelle" => "Autofinancement", "couleur" => "vert", "annee" => 2023 }
        ]
      },
      date: Date.new(2024, 6, 1)
    )
  end

  test "l'accueil répond 200 et liste toutes les communes triées par nom" do
    get root_path

    assert_response :success
    assert_select "[data-commune]", Commune.count
    noms = css_select("[data-commune] [data-nom]").map(&:text).map(&:strip)
    assert_equal Commune.order(:nom).pluck(:nom), noms
  end

  test "affiche le feu finances coloré d'une commune calculée" do
    get root_path

    carte = css_select("[data-commune='#{communes(:lyon).id}']").first
    assert_includes carte.to_s, "orange"
    assert_includes carte.to_s, "Exercice 2023"
  end

  test "affiche l'état neutre « non calculé » sans planter pour une commune sans feu" do
    assert_nil communes(:villeurbanne).feu("finances")

    get root_path

    carte = css_select("[data-commune='#{communes(:villeurbanne).id}']").first
    assert_includes carte.text, "Non calculé"
  end

  test "ne déclenche pas de N+1 sur les feux (une seule requête traffic_lights)" do
    requetes = 0
    abonnement = ->(*, payload) do
      sql = payload[:sql]
      requetes += 1 if sql.match?(/\btraffic_lights\b/i) && payload[:name] != "SCHEMA"
    end

    ActiveSupport::Notifications.subscribed(abonnement, "sql.active_record") do
      get root_path
    end

    assert_equal 1, requetes, "un seul SELECT sur traffic_lights attendu, quel que soit le nombre de communes"
  end
end
