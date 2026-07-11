require "test_helper"

module Eau
  class FeuTest < ActiveSupport::TestCase
    setup do
      @commune = communes(:lyon)
    end

    test "feu vert quand tous les prélèvements des 12 derniers mois sont conformes" do
      prelevement("P1", Date.new(2026, 3, 1), microbiologique: true, physicochimique: true, references_qualite: true)
      prelevement("P2", Date.new(2025, 12, 1), microbiologique: true, physicochimique: true, references_qualite: true)

      feu = Feu.recalculer!(@commune)

      assert_equal "vert", feu.couleur
      assert_equal %w[vert vert vert].sort, couleurs_indicateurs(feu).sort
    end

    test "orange sur une non-conformité microbiologique ponctuelle" do
      prelevement("P1", Date.new(2026, 3, 1), microbiologique: false, physicochimique: true)
      prelevement("P2", Date.new(2026, 1, 1), microbiologique: true, physicochimique: true)

      feu = Feu.recalculer!(@commune)

      assert_equal "orange", feu.couleur
      assert_equal "orange", couleur_indicateur(feu, "microbiologique")
      assert_equal 2, valeur_indicateur(feu, "microbiologique", "prelevements_evalues")
      assert_equal 1, valeur_indicateur(feu, "microbiologique", "prelevements_non_conformes")
    end

    test "rouge sur des non-conformités microbiologiques récurrentes" do
      prelevement("P1", Date.new(2026, 3, 1), microbiologique: false, physicochimique: true)
      prelevement("P2", Date.new(2026, 1, 1), microbiologique: false, physicochimique: true)

      feu = Feu.recalculer!(@commune)

      assert_equal "rouge", feu.couleur
      assert_equal "rouge", couleur_indicateur(feu, "microbiologique")
    end

    test "orange sur une non-conformité aux références de qualité, jamais rouge" do
      prelevement("P1", Date.new(2026, 3, 1), microbiologique: true, physicochimique: true, references_qualite: false)
      prelevement("P2", Date.new(2026, 1, 1), microbiologique: true, physicochimique: true, references_qualite: false)

      feu = Feu.recalculer!(@commune)

      assert_equal "orange", feu.couleur
      assert_equal "orange", couleur_indicateur(feu, "references_qualite")
    end

    test "le feu du domaine est la pire couleur des indicateurs" do
      prelevement("P1", Date.new(2026, 3, 1), microbiologique: false, physicochimique: false)
      prelevement("P2", Date.new(2026, 1, 1), microbiologique: false, physicochimique: true)

      feu = Feu.recalculer!(@commune)

      assert_equal "rouge", feu.couleur
    end

    test "les prélèvements de plus de 12 mois sont hors de la fenêtre" do
      # Ancre la fenêtre sur mars 2026 ; une non-conformité de janvier 2025 est exclue.
      prelevement("RECENT", Date.new(2026, 3, 1), microbiologique: true, physicochimique: true)
      prelevement("VIEUX", Date.new(2025, 1, 1), microbiologique: false, physicochimique: true)

      feu = Feu.recalculer!(@commune)

      assert_equal "vert", feu.couleur
      assert_equal 1, valeur_indicateur(feu, "microbiologique", "prelevements_evalues")
    end

    test "un indicateur sans prélèvement évalué est ignoré" do
      prelevement("P1", Date.new(2026, 3, 1), microbiologique: true)

      feu = Feu.recalculer!(@commune)

      assert_equal %w[microbiologique], feu.justification["indicateurs"].map { |i| i["indicateur"] }
    end

    test "la justification cite la période, la source, les chiffres et les seuils" do
      prelevement("P1", Date.new(2026, 3, 1), microbiologique: true, physicochimique: true, references_qualite: true)

      feu = Feu.recalculer!(@commune)

      assert_equal "2025-03-01", feu.justification["periode_debut"]
      assert_equal "2026-03-01", feu.justification["periode_fin"]
      assert_match %r{\Ahttps://hubeau}, feu.justification["source_url"]

      microbio = indicateur(feu, "microbiologique")
      assert_equal "Conformité microbiologique", microbio["libelle"]
      assert_equal 2, microbio.dig("seuils", "non_conformites_12_mois", "rouge_a_partir_de")
      assert_match(/11 janvier 2007/, microbio.dig("seuils", "non_conformites_12_mois", "reference"))
    end

    test "recalculer sans changement d'entrées n'ajoute pas de ligne" do
      prelevement("P1", Date.new(2026, 3, 1), microbiologique: true, physicochimique: true)
      Feu.recalculer!(@commune)

      assert_no_difference -> { TrafficLight.count } do
        Feu.recalculer!(@commune)
      end
    end

    test "recalculer après un changement d'entrée ajoute exactement une ligne" do
      prelevement("P1", Date.new(2026, 3, 1), microbiologique: true, physicochimique: true)
      Feu.recalculer!(@commune)
      prelevement("P2", Date.new(2026, 3, 15), microbiologique: false, physicochimique: true)

      assert_difference -> { TrafficLight.count }, 1 do
        Feu.recalculer!(@commune)
      end

      assert_equal "orange", @commune.feu("eau").couleur
    end

    test "sans mesures, pas de feu" do
      assert_nil Feu.recalculer!(@commune)
      assert_equal 0, TrafficLight.count
    end

    private

    def prelevement(code, date, conformites)
      conformites.each do |type, conforme|
        @commune.measurements.create!(
          domaine: "eau", indicateur: "#{type}:#{code}", valeur: conforme ? 1 : 0, date:,
          source_url: "https://hubeau.eaufrance.fr/api/v1/qualite_eau_potable/resultats_dis?code_commune=69123"
        )
      end
    end

    def indicateur(feu, nom)
      feu.justification["indicateurs"].find { |entree| entree["indicateur"] == nom }
    end

    def couleur_indicateur(feu, nom)
      indicateur(feu, nom)["couleur"]
    end

    def valeur_indicateur(feu, nom, cle)
      indicateur(feu, nom)["valeurs"][cle]
    end

    def couleurs_indicateurs(feu)
      feu.justification["indicateurs"].map { |entree| entree["couleur"] }
    end
  end
end
