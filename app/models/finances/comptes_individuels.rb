require "csv"
require "net/http"

# Source du module finances : « Comptes individuels des communes (fichier
# global) », données DGFiP publiées par les Ministères économiques et
# financiers sur data.gouv.fr sous Licence Ouverte v2.0, un jeu de données
# par millésime (ex. https://www.data.gouv.fr/datasets/comptes-individuels-des-communes-fichier-global-2023-2024),
# servies par l'API Opendatasoft de data.economie.gouv.fr.
#
# Montants en milliers d'euros ; colonnes fXXX = euros par habitant ;
# colonnes mXXX = moyenne de la strate démographique en euros par habitant.
# Le code INSEE est reconstruit à partir de `dep` (3 caractères, « 069 »
# pour le Rhône) et `icom` (3 caractères).
module Finances
  class ComptesIndividuels
    class ExportIndisponible < StandardError; end

    DATASETS = {
      2021 => "comptes-individuels-des-communes-fichier-global-2021",
      2022 => "comptes-individuels-des-communes-fichier-global-2022",
      2023 => "comptes-individuels-des-communes-fichier-global-2023-2024",
      2024 => "comptes-individuels-des-communes-fichier-global-2023-2024"
    }.freeze
    ANNEES = DATASETS.keys.freeze

    # Colonnes DGFiP → indicateurs Communoscope (stockés dans measurements)
    INDICATEURS = {
      "prod" => "produits_fonctionnement",
      "perso" => "charges_personnel",
      "cont" => "contingents",
      "fin" => "charges_financieres",
      "caf" => "caf_brute",
      "dette" => "encours_dette",
      "fdette" => "dette_par_habitant",
      "mdette" => "dette_par_habitant_strate",
      "fcaf" => "caf_par_habitant",
      "mcaf" => "caf_par_habitant_strate"
    }.freeze

    DEPARTEMENT_METROPOLE = "069"

    class << self
      def source_url(annee)
        "https://www.data.gouv.fr/datasets/#{DATASETS.fetch(annee)}"
      end

      def export_url(annee)
        champs = (%w[an dep icom] + INDICATEURS.keys).join(",")
        filtre = CGI.escape(%(dep="#{DEPARTEMENT_METROPOLE}" and an="#{annee}"))
        "https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/#{DATASETS.fetch(annee)}" \
          "/exports/csv?select=#{champs}&where=#{filtre}&delimiter=%3B"
      end

      def csv(annee)
        url = export_url(annee)
        reponse = Net::HTTP.get_response(URI(url))
        unless reponse.is_a?(Net::HTTPSuccess)
          raise ExportIndisponible, "HTTP #{reponse.code} sur #{url}"
        end

        reponse.body
      end

      def mesures(annee)
        # L'export CSV Opendatasoft commence par un BOM UTF-8 (EF BB BF) qui,
        # laissé en place, polluerait le premier en-tête ("an" → "﻿an").
        corps = csv(annee).dup.force_encoding("UTF-8").delete_prefix("﻿")

        CSV.parse(corps, headers: true, col_sep: ";").filter_map do |ligne|
          next unless ligne["an"].to_i == annee

          valeurs = INDICATEURS.filter_map do |colonne, indicateur|
            [ indicateur, Float(ligne[colonne]) ] if ligne[colonne].present?
          end.to_h

          { code_insee: ligne["dep"].delete_prefix("0") + ligne["icom"], valeurs: }
        end
      end
    end
  end
end
