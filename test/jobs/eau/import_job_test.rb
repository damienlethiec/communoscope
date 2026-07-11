require "test_helper"

module Eau
  class ImportJobTest < ActiveJob::TestCase
    test "importe les prélèvements des communes de la métropole présentes en base" do
      importe

      # Lyon : 2 prélèvements × 3 conformités ; Villeurbanne : 3 × 3.
      assert_equal 15, Measurement.count
      assert_equal 15, Measurement.where(domaine: "eau").count

      mesure = communes(:lyon).measurements.find_by(indicateur: "microbiologique:06900175457")
      assert_equal 1.0, mesure.valeur.to_f
      assert_equal Date.new(2026, 3, 10), mesure.date
      assert_equal QualiteEauPotable.source_url, mesure.source_url
    end

    test "rejouer l'import sur les mêmes données ne crée aucun doublon" do
      importe

      assert_no_difference -> { Measurement.count } do
        importe
      end
    end

    test "calcule les feux des communes importées" do
      importe

      assert_equal "vert", communes(:lyon).feu("eau").couleur
      assert_equal "rouge", communes(:villeurbanne).feu("eau").couleur
    end

    test "rejouer l'import n'ajoute pas de ligne de feu" do
      importe

      assert_no_difference -> { TrafficLight.count } do
        importe
      end
    end

    test "une conformité corrigée à la source met à jour la mesure et historise le feu" do
      importe
      assert_equal "rouge", communes(:villeurbanne).feu("eau").couleur

      # La 2e non-conformité de Villeurbanne repasse conforme : plus qu'une seule
      # non-conformité ponctuelle → orange.
      corrige = donnees
      corrige["69266"] = corrige["69266"].map do |ligne|
        ligne = ligne.dup
        ligne["conformite_limites_bact_prelevement"] = "C" if ligne["code_prelevement"] == "06900172233"
        ligne
      end

      assert_difference -> { TrafficLight.count }, 1 do
        assert_no_difference -> { Measurement.count } do
          importe(donnees: corrige)
        end
      end

      assert_equal "orange", communes(:villeurbanne).feu("eau").couleur
    end

    test "une commune indisponible n'empêche pas les autres et lève à la fin" do
      resultats = lambda do |code, _date_min|
        raise QualiteEauPotable::AnalysesIndisponibles, "HTTP 503" if code == "69266"

        donnees.fetch(code)
      end

      erreur = assert_raises(QualiteEauPotable::AnalysesIndisponibles) do
        stub_classe(QualiteEauPotable, :resultats, resultats) { ImportJob.perform_now }
      end
      assert_match(/69266/, erreur.message)

      assert_equal "vert", communes(:lyon).feu("eau").couleur
      assert_nil communes(:villeurbanne).feu("eau")
    end

    private

    def importe(donnees: donnees())
      stub_classe(QualiteEauPotable, :resultats, ->(code, _date_min) { donnees.fetch(code) }) do
        ImportJob.perform_now
      end
    end

    def donnees
      @donnees ||= {
        "69123" => fixture_data("lyon_conforme"),
        "69266" => fixture_data("villeurbanne_non_conforme")
      }
    end

    def fixture_data(nom)
      JSON.parse(file_fixture("eau/#{nom}.json").read).fetch("data")
    end
  end
end
