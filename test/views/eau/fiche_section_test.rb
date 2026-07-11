require "test_helper"

module Eau
  class FicheSectionTest < ActionView::TestCase
    test "affiche le feu, la période, les chiffres, les seuils et la source" do
      commune = communes(:lyon)
      prelevement(commune, "P1", Date.new(2026, 3, 1), microbiologique: true, physicochimique: true, references_qualite: true)
      Feu.recalculer!(commune)

      render partial: "eau/fiche_section", locals: { commune: }

      assert_includes rendered, "Eau potable"
      assert_includes rendered, "vert"
      assert_includes rendered, "Conformité microbiologique"
      assert_includes rendered, "Conformité physico-chimique"
      assert_includes rendered, "11 janvier 2007"
      assert_includes rendered, "hubeau.eaufrance.fr"
    end

    test "affiche la couleur d'un indicateur dégradé" do
      commune = communes(:lyon)
      prelevement(commune, "P1", Date.new(2026, 3, 1), microbiologique: false, physicochimique: true)
      prelevement(commune, "P2", Date.new(2026, 1, 1), microbiologique: false, physicochimique: true)
      Feu.recalculer!(commune)

      render partial: "eau/fiche_section", locals: { commune: }

      assert_includes rendered, "rouge"
    end

    test "signale l'absence de données sans feu calculé" do
      render partial: "eau/fiche_section", locals: { commune: communes(:lyon) }

      assert_includes rendered, "Données sur l'eau potable indisponibles"
    end

    private

    def prelevement(commune, code, date, conformites)
      conformites.each do |type, conforme|
        commune.measurements.create!(
          domaine: "eau", indicateur: "#{type}:#{code}", valeur: conforme ? 1 : 0, date:,
          source_url: "https://hubeau.eaufrance.fr/api/v1/qualite_eau_potable/resultats_dis?code_commune=69123"
        )
      end
    end
  end
end
