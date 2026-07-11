require "test_helper"

class CommunesShowTest < ActionDispatch::IntegrationTest
  test "la fiche répond 200 et affiche le nom de la commune" do
    get commune_path(communes(:lyon).code_insee)

    assert_response :success
    assert_select "h1", /Lyon/
  end

  test "affiche le feu finances, sa justification chiffrée, ses seuils et sa source" do
    feu_finances(communes(:lyon), "orange")

    get commune_path(communes(:lyon).code_insee)

    assert_select "#finances"
    assert_includes response.body, "Endettement"
    assert_includes response.body, "Capacité de désendettement" # libellé de valeur
    assert_includes response.body, "loi n° 2018-32"             # référence du seuil
    assert_includes response.body, "https://www.data.gouv.fr/datasets/comptes-2023" # source
  end

  test "affiche le feu eau et sa justification" do
    feu_eau(communes(:lyon), "rouge")

    get commune_path(communes(:lyon).code_insee)

    assert_select "#eau"
    assert_includes response.body, "Microbiologie"
    assert_includes response.body, "Prélèvements non conformes"
    assert_includes response.body, "hubeau.eaufrance.fr"
  end

  test "affiche l'historique des changements de feu du plus récent au plus ancien" do
    feu_finances(communes(:lyon), "vert")
    feu_finances(communes(:lyon), "orange") # changement => nouvelle ligne

    get commune_path(communes(:lyon).code_insee)

    assert_includes response.body, "Historique"
    couleurs = css_select("[data-historique]").map { |n| n["data-couleur"] }
    assert_equal %w[orange vert], couleurs, "le plus récent (orange) en premier"
  end

  test "commune sans feu : état neutre, pas de crash" do
    get commune_path(communes(:villeurbanne).code_insee)

    assert_response :success
    assert_includes response.body, "Données financières indisponibles"
    assert_includes response.body, "Données sur l'eau potable indisponibles"
  end

  test "code INSEE inconnu : 404" do
    get commune_path("00000")

    assert_response :not_found
  end

  private

  def feu_finances(commune, couleur)
    TrafficLight.enregistrer!(
      commune:, domaine: "finances", couleur:, date: Date.new(2024, 6, 1),
      justification: {
        "annee" => 2023,
        "source_url" => "https://www.data.gouv.fr/datasets/comptes-2023",
        "indicateurs" => [
          {
            "indicateur" => "endettement", "libelle" => "Endettement", "couleur" => couleur, "annee" => 2023,
            "valeurs" => { "capacite_desendettement_annees" => 8.5, "encours_dette" => 6_000 },
            "seuils" => { "orange" => { "reference" => "loi n° 2018-32", "url" => "https://www.legifrance.gouv.fr" } },
            "source_url" => "https://www.data.gouv.fr/datasets/comptes-2023"
          }
        ]
      }
    )
  end

  def feu_eau(commune, couleur)
    TrafficLight.enregistrer!(
      commune:, domaine: "eau", couleur:, date: Date.new(2024, 1, 15),
      justification: {
        "periode_debut" => "2023-01-01",
        "periode_fin" => "2023-12-31",
        "source_url" => "https://hubeau.eaufrance.fr",
        "indicateurs" => [
          {
            "indicateur" => "microbiologique", "libelle" => "Microbiologie", "couleur" => couleur,
            "valeurs" => { "prelevements_evalues" => 10, "prelevements_non_conformes" => 3 },
            "seuils" => { "non_conformites_12_mois" => { "reference" => "arrêté du 11 janvier 2007" } }
          }
        ]
      }
    )
  end
end
