require "test_helper"

module Finances
  class FeuTest < ActiveSupport::TestCase
    # Jeu de base « dans les clous » : capacité de désendettement 4 ans,
    # dette/hab à 80 % de la strate, taux de CAF brute 15 %, rigidité 46 %.
    MESURES_VERTES = {
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

    setup do
      @commune = communes(:lyon)
    end

    test "feu vert quand tous les indicateurs sont dans les clous" do
      cree_mesures

      feu = Feu.recalculer!(@commune)

      assert_equal "vert", feu.couleur
      assert_equal %w[vert vert vert], couleurs_indicateurs(feu)
    end

    test "endettement orange quand la capacité de désendettement dépasse 8 ans" do
      cree_mesures("encours_dette" => 13_500)

      feu = Feu.recalculer!(@commune)

      assert_equal "orange", feu.couleur
      assert_equal "orange", couleur_indicateur(feu, "endettement")
      assert_equal 9.0, valeur_indicateur(feu, "endettement", "capacite_desendettement_annees")
    end

    test "endettement rouge quand la capacité de désendettement dépasse 12 ans" do
      cree_mesures("encours_dette" => 19_500)

      feu = Feu.recalculer!(@commune)

      assert_equal "rouge", feu.couleur
      assert_equal "rouge", couleur_indicateur(feu, "endettement")
    end

    test "endettement rouge quand la CAF est négative avec une dette non nulle" do
      cree_mesures("caf_brute" => -100)

      feu = Feu.recalculer!(@commune)

      assert_equal "rouge", couleur_indicateur(feu, "endettement")
      assert_nil valeur_indicateur(feu, "endettement", "capacite_desendettement_annees")
    end

    test "endettement vert sans dette même avec une CAF négative" do
      cree_mesures("caf_brute" => -100, "encours_dette" => 0, "dette_par_habitant" => 0)

      feu = Feu.recalculer!(@commune)

      assert_equal "vert", couleur_indicateur(feu, "endettement")
    end

    test "endettement orange quand la dette par habitant dépasse 1,2 fois la strate" do
      cree_mesures("dette_par_habitant" => 1_300)

      feu = Feu.recalculer!(@commune)

      assert_equal "orange", couleur_indicateur(feu, "endettement")
      assert_equal 1.3, valeur_indicateur(feu, "endettement", "ratio_dette_habitant_strate")
    end

    test "autofinancement orange sous 12 % de taux de CAF brute" do
      cree_mesures("caf_brute" => 1_000)

      feu = Feu.recalculer!(@commune)

      assert_equal "orange", couleur_indicateur(feu, "autofinancement")
      assert_equal 10.0, valeur_indicateur(feu, "autofinancement", "taux_caf_brute_pct")
    end

    test "autofinancement rouge sous 8 % de taux de CAF brute" do
      cree_mesures("caf_brute" => 700)

      feu = Feu.recalculer!(@commune)

      assert_equal "rouge", couleur_indicateur(feu, "autofinancement")
    end

    test "rigidité orange au-delà de 55 % des produits" do
      cree_mesures("charges_personnel" => 5_000)

      feu = Feu.recalculer!(@commune)

      assert_equal "orange", couleur_indicateur(feu, "rigidite_charges")
      assert_equal 56.0, valeur_indicateur(feu, "rigidite_charges", "rigidite_pct")
    end

    test "rigidité rouge au-delà de 65 % des produits" do
      cree_mesures("charges_personnel" => 6_000)

      feu = Feu.recalculer!(@commune)

      assert_equal "rouge", couleur_indicateur(feu, "rigidite_charges")
    end

    test "le feu du domaine est la pire couleur des indicateurs" do
      cree_mesures("caf_brute" => 1_000, "charges_personnel" => 6_000)

      feu = Feu.recalculer!(@commune)

      assert_equal "rouge", feu.couleur
    end

    test "la justification cite l'année, la source, les chiffres et les seuils" do
      cree_mesures

      feu = Feu.recalculer!(@commune)

      assert_equal 2023, feu.justification["annee"]
      assert_match %r{\Ahttps://}, feu.justification["source_url"]

      endettement = indicateur(feu, "endettement")
      assert_equal "Endettement", endettement["libelle"]
      assert_match %r{\Ahttps://}, endettement["source_url"]
      assert_equal 4.0, endettement["valeurs"]["capacite_desendettement_annees"]
      assert_equal 12.0, endettement.dig("seuils", "capacite_desendettement_annees", "rouge_au_dela_de")
      assert_match(/loi n° 2018-32/, endettement.dig("seuils", "capacite_desendettement_annees", "reference"))
    end

    test "recalculer sans changement d'entrées n'ajoute pas de ligne" do
      cree_mesures
      Feu.recalculer!(@commune)

      assert_no_difference -> { TrafficLight.count } do
        Feu.recalculer!(@commune)
      end
    end

    test "recalculer après un changement d'entrée ajoute exactement une ligne" do
      cree_mesures
      Feu.recalculer!(@commune)
      cree_mesures("caf_brute" => 700)

      assert_difference -> { TrafficLight.count }, 1 do
        Feu.recalculer!(@commune)
      end
    end

    test "utilise l'exercice le plus récent" do
      cree_mesures("caf_brute" => 700, annee: 2022)
      cree_mesures(annee: 2023)

      feu = Feu.recalculer!(@commune)

      assert_equal "vert", feu.couleur
      assert_equal 2023, feu.justification["annee"]
    end

    test "un indicateur manquant sur le dernier exercice n'améliore pas le feu (repli)" do
      # 2023 complet et rouge sur l'endettement, 2024 sans les colonnes de dette.
      cree_mesures("encours_dette" => 19_500, annee: 2023)
      cree_mesures_seulement(
        %w[caf_brute produits_fonctionnement charges_personnel contingents
           charges_financieres caf_par_habitant caf_par_habitant_strate],
        annee: 2024
      )

      feu = Feu.recalculer!(@commune)

      assert_equal "rouge", feu.couleur
      assert_equal "rouge", couleur_indicateur(feu, "endettement")
      assert_equal 2023, indicateur(feu, "endettement")["annee"]
      assert_equal 2024, indicateur(feu, "autofinancement")["annee"]
      assert_equal source_url(2023), indicateur(feu, "endettement")["source_url"]
      assert_equal source_url(2024), indicateur(feu, "autofinancement")["source_url"]
    end

    test "sans mesures, pas de feu" do
      assert_nil Feu.recalculer!(@commune)
      assert_equal 0, TrafficLight.count
    end

    private

    def cree_mesures(valeurs = {})
      annee = valeurs.delete(:annee) || 2023
      cree(MESURES_VERTES.merge(valeurs), annee)
    end

    def cree_mesures_seulement(indicateurs, annee:)
      cree(MESURES_VERTES.slice(*indicateurs), annee)
    end

    def cree(valeurs, annee)
      valeurs.each do |indicateur, valeur|
        Measurement
          .find_or_initialize_by(commune: @commune, domaine: "finances", indicateur:, date: Date.new(annee, 12, 31))
          .update!(valeur:, source_url: source_url(annee))
      end
    end

    def source_url(annee)
      "https://www.data.gouv.fr/datasets/comptes-individuels-des-communes-fichier-global-#{annee}"
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
