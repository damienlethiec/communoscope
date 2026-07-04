require "test_helper"

module Finances
  class FicheSectionTest < ActionView::TestCase
    MESURES = {
      "encours_dette" => 6_000,
      "caf_brute" => 1_500,
      "produits_fonctionnement" => 10_000,
      "charges_personnel" => 4_000,
      "contingents" => 500,
      "charges_financieres" => 100,
      "dette_par_habitant" => 800,
      "dette_par_habitant_strate" => 1_000,
      "caf_par_habitant" => 150,
      "caf_par_habitant_strate" => 160
    }.freeze

    test "affiche le feu, l'exercice, les chiffres, les seuils et la source" do
      commune = communes(:lyon)
      cree_mesures(commune)
      Feu.recalculer!(commune)

      render partial: "finances/fiche_section", locals: { commune: }

      assert_includes rendered, "Finances"
      assert_includes rendered, "vert"
      assert_includes rendered, "Exercice 2024"
      assert_includes rendered, "Endettement"
      assert_includes rendered, "Capacité d&#39;autofinancement"
      assert_includes rendered, "Rigidité des charges"
      assert_includes rendered, "Capacité de désendettement"
      assert_includes rendered, "loi n° 2018-32"
      assert_includes rendered, "https://www.data.gouv.fr/datasets/comptes-individuels-des-communes-fichier-global-2023-2024"
    end

    test "affiche la couleur de chaque indicateur dégradé" do
      commune = communes(:lyon)
      cree_mesures(commune, "caf_brute" => 700)
      Feu.recalculer!(commune)

      render partial: "finances/fiche_section", locals: { commune: }

      assert_includes rendered, "rouge"
    end

    test "signale l'absence de données sans feu calculé" do
      render partial: "finances/fiche_section", locals: { commune: communes(:lyon) }

      assert_includes rendered, "Données financières indisponibles"
    end

    private

    def cree_mesures(commune, valeurs = {})
      MESURES.merge(valeurs).each do |indicateur, valeur|
        commune.measurements.create!(
          domaine: "finances", indicateur:, valeur:, date: Date.new(2024, 12, 31),
          source_url: "https://www.data.gouv.fr/datasets/comptes-individuels-des-communes-fichier-global-2023-2024"
        )
      end
    end
  end
end
