require "test_helper"

module Finances
  class ComptesIndividuelsTest < ActiveSupport::TestCase
    test "l'URL d'export filtre le millésime et le département de la métropole" do
      url = ComptesIndividuels.export_url(2024)

      assert_includes url, "comptes-individuels-des-communes-fichier-global-2023-2024/exports/csv"
      assert_includes url, CGI.escape(%(dep="069" and an="2024"))
    end

    test "refuse un millésime inconnu" do
      assert_raises(KeyError) { ComptesIndividuels.export_url(1999) }
    end

    test "source_url pointe vers la page data.gouv.fr du millésime" do
      assert_equal "https://www.data.gouv.fr/datasets/comptes-individuels-des-communes-fichier-global-2022",
        ComptesIndividuels.source_url(2022)
    end

    test "csv renvoie le corps de la réponse en cas de succès HTTP" do
      reponse = Net::HTTPOK.new("1.1", "200", "OK")
      reponse.define_singleton_method(:body) { "an;dep;icom\n" }

      corps = stub_classe(Net::HTTP, :get_response, reponse) do
        ComptesIndividuels.csv(2023)
      end

      assert_equal "an;dep;icom\n", corps
    end

    test "csv lève une erreur explicite sur statut HTTP non 2xx" do
      reponse = Net::HTTPTooManyRequests.new("1.1", "429", "Too Many Requests")

      erreur = stub_classe(Net::HTTP, :get_response, reponse) do
        assert_raises(ComptesIndividuels::ExportIndisponible) { ComptesIndividuels.csv(2023) }
      end

      assert_includes erreur.message, "429"
      assert_includes erreur.message, ComptesIndividuels.export_url(2023)
    end

    test "mesures transforme les lignes CSV en indicateurs par code INSEE" do
      mesures = stub_classe(ComptesIndividuels, :csv, file_fixture("finances/comptes_individuels_2023.csv").read) do
        ComptesIndividuels.mesures(2023)
      end

      assert_equal 4, mesures.size

      lyon = mesures.find { |mesure| mesure[:code_insee] == "69123" }
      assert_equal 778633.43, lyon[:valeurs]["produits_fonctionnement"]
      assert_equal 365673.81, lyon[:valeurs]["charges_personnel"]
      assert_equal 8560.87, lyon[:valeurs]["contingents"]
      assert_equal 5279.09, lyon[:valeurs]["charges_financieres"]
      assert_equal 122147.02, lyon[:valeurs]["caf_brute"]
      assert_equal 322368.93, lyon[:valeurs]["encours_dette"]
      assert_equal 609.82, lyon[:valeurs]["dette_par_habitant"]
      assert_equal 1079.08, lyon[:valeurs]["dette_par_habitant_strate"]
      assert_equal 231.06, lyon[:valeurs]["caf_par_habitant"]
      assert_equal 216.33, lyon[:valeurs]["caf_par_habitant_strate"]
    end

    test "mesures ignore les lignes d'un autre exercice" do
      mesures = stub_classe(ComptesIndividuels, :csv, file_fixture("finances/comptes_individuels_2023.csv").read) do
        ComptesIndividuels.mesures(2024)
      end

      assert_empty mesures
    end
  end
end
