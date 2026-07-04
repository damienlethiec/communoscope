require "test_helper"

module Finances
  class ImportJobTest < ActiveJob::TestCase
    ANNEES_FIXTURES = [ 2022, 2023, 2024 ].freeze

    test "importe les mesures des communes de la métropole présentes en base" do
      importe

      # 2 communes en base (Lyon, Villeurbanne) × 10 indicateurs × 3 exercices
      assert_equal 60, Measurement.count
      assert_equal 60, Measurement.where(domaine: "finances").count

      dette = communes(:lyon).measurements.find_by(indicateur: "encours_dette", date: Date.new(2024, 12, 31))
      assert_in_delta 319274.27, dette.valeur.to_f
      assert_equal ComptesIndividuels.source_url(2024), dette.source_url
    end

    test "ignore les communes absentes de la base (filtre code INSEE)" do
      importe

      assert_empty Measurement.joins(:commune).where.not(communes: { code_insee: %w[69123 69266] })
    end

    test "rejouer l'import sur les mêmes fichiers ne crée aucun doublon" do
      importe

      assert_no_difference -> { Measurement.count } do
        importe
      end
    end

    test "calcule les feux des communes importées" do
      importe

      feu = communes(:lyon).feu("finances")
      assert_equal "vert", feu.couleur
      assert_equal 2024, feu.justification["annee"]
      assert_equal "vert", communes(:villeurbanne).feu("finances").couleur
    end

    test "rejouer l'import n'ajoute pas de ligne de feu" do
      importe

      assert_no_difference -> { TrafficLight.count } do
        importe
      end
    end

    test "une valeur corrigée à la source met à jour la mesure et historise le feu" do
      importe

      # CAF brute 2024 de Lyon effondrée : taux de CAF ~0,6 % → rouge
      csv_corrige = fichiers_fixtures.transform_values do |csv|
        csv.gsub("106063.44", "5000.0")
      end

      assert_difference -> { TrafficLight.count }, 1 do
        assert_no_difference -> { Measurement.count } do
          importe(fichiers: csv_corrige)
        end
      end

      assert_equal "rouge", communes(:lyon).feu("finances").couleur
    end

    private

    def importe(fichiers: fichiers_fixtures)
      stub_classe(ComptesIndividuels, :csv, ->(annee) { fichiers.fetch(annee) }) do
        ImportJob.perform_now(*ANNEES_FIXTURES)
      end
    end

    def fichiers_fixtures
      @fichiers_fixtures ||= ANNEES_FIXTURES.index_with do |annee|
        file_fixture("finances/comptes_individuels_#{annee}.csv").read
      end
    end
  end
end
