require "test_helper"

module Eau
  class QualiteEauPotableTest < ActiveSupport::TestCase
    test "l'URL d'export filtre la commune, la date et les champs de conformité" do
      url = QualiteEauPotable.resultats_url("69123", "2025-06-01")

      assert_includes url, "qualite_eau_potable/resultats_dis"
      assert_includes url, "code_commune=69123"
      assert_includes url, "date_min_prelevement=2025-06-01"
      assert_includes url, "conformite_limites_bact_prelevement"
    end

    test "source_url pointe vers la page de documentation Hub'Eau lisible" do
      assert_equal "https://hubeau.eaufrance.fr/page/api-qualite-eau-potable",
        QualiteEauPotable.source_url
    end

    test "resultats suit la pagination et concatène les pages" do
      reponse = lambda do |uri|
        page = uri.to_s.include?("page=2") ? "pagination_page2" : "pagination_page1"
        r = Net::HTTPOK.new("1.1", "200", "OK")
        corps = file_fixture("eau/#{page}.json").read
        r.define_singleton_method(:body) { corps }
        r
      end

      lignes = stub_classe(Net::HTTP, :get_response, reponse) do
        QualiteEauPotable.resultats("69123", "2025-01-01")
      end

      assert_equal 2, lignes.size
      assert_equal %w[06900175457 06900168002], lignes.map { |l| l["code_prelevement"] }
    end

    test "resultats lève une erreur explicite sur statut HTTP non 2xx" do
      reponse = Net::HTTPTooManyRequests.new("1.1", "429", "Too Many Requests")

      erreur = stub_classe(Net::HTTP, :get_response, reponse) do
        assert_raises(QualiteEauPotable::AnalysesIndisponibles) do
          QualiteEauPotable.resultats("69123", "2025-01-01")
        end
      end

      assert_includes erreur.message, "429"
    end

    test "resultats convertit une erreur réseau en AnalysesIndisponibles" do
      reponse = ->(_uri) { raise SocketError, "getaddrinfo: nodename nor servname provided" }

      stub_classe(Net::HTTP, :get_response, reponse) do
        assert_raises(QualiteEauPotable::AnalysesIndisponibles) do
          QualiteEauPotable.resultats("69123", "2025-01-01")
        end
      end
    end

    test "resultats convertit une réponse JSON invalide en AnalysesIndisponibles" do
      reponse = lambda do |_uri|
        r = Net::HTTPOK.new("1.1", "200", "OK")
        r.define_singleton_method(:body) { "<html>maintenance</html>" }
        r
      end

      stub_classe(Net::HTTP, :get_response, reponse) do
        assert_raises(QualiteEauPotable::AnalysesIndisponibles) do
          QualiteEauPotable.resultats("69123", "2025-01-01")
        end
      end
    end

    test "prelevements dédoublonne par code_prelevement et mappe les conformités" do
      prelevements = stub_classe(QualiteEauPotable, :resultats, fixture_data("lyon_conforme")) do
        QualiteEauPotable.prelevements("69123", "2025-01-01")
      end

      assert_equal 2, prelevements.size

      recent = prelevements.find { |p| p[:code] == "06900175457" }
      assert_equal Date.new(2026, 3, 10), recent[:date]
      assert_equal true, recent[:conformites]["microbiologique"]
      assert_equal true, recent[:conformites]["physicochimique"]
      assert_equal true, recent[:conformites]["references_qualite"]
    end

    test "prelevements marque non conforme un prélèvement N et laisse indéterminé un champ absent" do
      lignes = [
        {
          "code_prelevement" => "P1", "date_prelevement" => "2026-01-05T09:00:00Z",
          "conformite_limites_bact_prelevement" => "N",
          "conformite_limites_pc_prelevement" => "C",
          "conformite_references_bact_prelevement" => nil,
          "conformite_references_pc_prelevement" => nil
        }
      ]

      prelevement = stub_classe(QualiteEauPotable, :resultats, lignes) do
        QualiteEauPotable.prelevements("69123", "2025-01-01")
      end.first

      assert_equal false, prelevement[:conformites]["microbiologique"]
      assert_equal true, prelevement[:conformites]["physicochimique"]
      assert_nil prelevement[:conformites]["references_qualite"]
    end

    private

    def fixture_data(nom)
      JSON.parse(file_fixture("eau/#{nom}.json").read).fetch("data")
    end
  end
end
