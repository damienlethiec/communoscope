require "test_helper"

class CommunesControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Jeu de communes couvrant tous les cas de filtrage :
    #   lyon        : finances orange, eau rouge
    #   bron        : finances vert (créée ici)
    #   venissieux  : finances vert, nom accentué (recherche insensible aux accents)
    #   villeurbanne: aucun feu (état neutre)
    @bron = Commune.create!(code_insee: "69029", nom: "Bron", population: 40_000)
    @venissieux = Commune.create!(code_insee: "69259", nom: "Vénissieux", population: 65_000)

    feu_finances(communes(:lyon), "orange")
    feu_finances(@bron, "vert")
    feu_finances(@venissieux, "vert")
    feu_eau(communes(:lyon), "rouge")
  end

  test "l'accueil répond 200 et liste toutes les communes triées par nom" do
    get root_path

    assert_response :success
    assert_select "[data-commune]", Commune.count
    noms = css_select("[data-commune] [data-nom]").map(&:text).map(&:strip)
    assert_equal Commune.order(:nom).pluck(:nom), noms
  end

  test "chaque carte montre les deux feux (finances ET eau)" do
    get root_path

    carte = carte(communes(:lyon))
    assert_select_dans carte, "[data-feu='finances']"
    assert_select_dans carte, "[data-feu='eau']"
    # Le feu porte un libellé, pas seulement une couleur (accessibilité RGAA).
    assert_includes carte.text, "Vigilance"
    assert_includes carte.text, "Alerte"
  end

  test "affiche l'état neutre « non calculé » sans planter pour une commune sans feu" do
    assert_nil communes(:villeurbanne).feu("finances")
    assert_nil communes(:villeurbanne).feu("eau")

    get root_path

    carte = carte(communes(:villeurbanne))
    assert_equal 2, carte.text.scan("Non calculé").size
  end

  test "chaque commune est cliquable vers sa fiche" do
    get root_path

    carte = carte(communes(:lyon))
    assert_includes carte.to_s, commune_path(communes(:lyon).code_insee)
  end

  test "filtre par couleur rouge : seules les communes en rouge (tous domaines confondus)" do
    get root_path(couleur: "rouge")

    assert_response :success
    assert_equal [ communes(:lyon).id ], codes_affiches
  end

  test "filtre par couleur vert : les communes ayant au moins un feu vert" do
    get root_path(couleur: "vert")

    assert_equal [ @bron.id, @venissieux.id ].sort, codes_affiches.sort
  end

  test "filtre par domaine eau : seules les communes ayant un feu eau" do
    get root_path(domaine: "eau")

    assert_equal [ communes(:lyon).id ], codes_affiches
  end

  test "filtre par domaine finances : seules les communes ayant un feu finances" do
    get root_path(domaine: "finances")

    assert_equal [ @bron.id, communes(:lyon).id, @venissieux.id ].sort, codes_affiches.sort
  end

  test "filtres couleur et domaine combinables" do
    get root_path(domaine: "finances", couleur: "rouge")
    assert_empty codes_affiches, "aucun feu finances rouge"

    get root_path(domaine: "finances", couleur: "orange")
    assert_equal [ communes(:lyon).id ], codes_affiches
  end

  test "recherche par nom insensible à la casse et aux accents" do
    get root_path(q: "venissieux")

    assert_equal [ @venissieux.id ], codes_affiches
  end

  test "recherche combinable avec un filtre" do
    get root_path(q: "on", couleur: "vert")

    assert_equal [ @bron.id ], codes_affiches
  end

  test "ne déclenche pas de N+1 : une requête traffic_lights par domaine" do
    requetes = 0
    abonnement = ->(*, payload) do
      sql = payload[:sql]
      requetes += 1 if sql.match?(/\btraffic_lights\b/i) && payload[:name] != "SCHEMA"
    end

    ActiveSupport::Notifications.subscribed(abonnement, "sql.active_record") do
      get root_path
    end

    assert_equal 2, requetes, "un SELECT par domaine (finances, eau), indépendant du nombre de communes"
  end

  private

  def feu_finances(commune, couleur)
    TrafficLight.enregistrer!(
      commune:, domaine: "finances", couleur:, date: Date.new(2024, 6, 1),
      justification: {
        "annee" => 2023,
        "source_url" => "https://data.economie.gouv.fr",
        "indicateurs" => [
          { "indicateur" => "endettement", "libelle" => "Endettement", "couleur" => couleur, "annee" => 2023 }
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
          { "indicateur" => "microbiologique", "libelle" => "Microbiologie", "couleur" => couleur,
            "valeurs" => { "prelevements_evalues" => 10, "prelevements_non_conformes" => 3 },
            "seuils" => {} }
        ]
      }
    )
  end

  def carte(commune)
    css_select("[data-commune='#{commune.id}']").first
  end

  def codes_affiches
    css_select("[data-commune]").map { |n| n["data-commune"].to_i }
  end

  def assert_select_dans(node, selector)
    assert node.css(selector).any?, "attendu #{selector} dans la carte"
  end
end
