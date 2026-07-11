require "date"
require "json"
require "net/http"
require "openssl"

# Source du module eau potable : API Hub'Eau « qualité de l'eau potable »
# (https://hubeau.eaufrance.fr/page/api-qualite-eau-potable), qui expose les
# résultats du contrôle sanitaire de l'eau distribuée (données SISE-Eaux
# produites par les ARS pour le Ministère de la Santé), sous Licence Ouverte /
# Open Licence Etalab 2.0.
#
# Endpoint utilisé : `/api/v1/qualite_eau_potable/resultats_dis`, filtré par
# `code_commune` (INSEE) et `date_min_prelevement`. Chaque enregistrement de
# l'API est une analyse (un paramètre d'un prélèvement) ; les champs de
# conformité (`conformite_limites_bact_prelevement`, `..._pc_prelevement`,
# `conformite_references_bact_prelevement`, `..._pc_prelevement`) sont portés au
# niveau du prélèvement et valent « C » (conforme) ou « N » (non conforme). On
# regroupe donc les analyses par `code_prelevement` pour ne garder qu'une ligne
# de conformité par prélèvement.
module Eau
  class QualiteEauPotable
    class AnalysesIndisponibles < StandardError; end

    API_BASE = "https://hubeau.eaufrance.fr/api/v1/qualite_eau_potable/resultats_dis"
    # Page de documentation lisible de l'API, affichée comme lien « Source » de la
    # fiche (l'endpoint JSON n'est pas destiné aux visiteurs).
    DOC_URL = "https://hubeau.eaufrance.fr/page/api-qualite-eau-potable"
    LICENCE = "Licence Ouverte / Open Licence Etalab 2.0"
    TAILLE_PAGE = 5_000

    # Toute défaillance de la frontière HTTP/JSON/parse est remontée en
    # AnalysesIndisponibles, pour que l'isolation d'erreur par commune de
    # ImportJob couvre aussi les incidents réseau et les réponses malformées.
    ERREURS_FRONTIERE = [
      Net::OpenTimeout, Net::ReadTimeout, IOError, SocketError, SystemCallError,
      OpenSSL::SSL::SSLError, JSON::ParserError, KeyError, Date::Error
    ].freeze

    # Champs demandés à l'API (limite le volume : on n'a besoin que de
    # l'identité du prélèvement et de ses conformités).
    CHAMPS = %w[
      code_commune code_prelevement date_prelevement conclusion_conformite_prelevement
      conformite_limites_bact_prelevement conformite_limites_pc_prelevement
      conformite_references_bact_prelevement conformite_references_pc_prelevement
    ].freeze

    class << self
      def source_url
        DOC_URL
      end

      def resultats_url(code_insee, date_min)
        params = {
          code_commune: code_insee,
          date_min_prelevement: date_min,
          fields: CHAMPS.join(","),
          size: TAILLE_PAGE
        }
        "#{API_BASE}?#{URI.encode_www_form(params)}"
      end

      # Toutes les analyses de la commune depuis `date_min`, pagination suivie.
      def resultats(code_insee, date_min)
        url = resultats_url(code_insee, date_min)
        lignes = []
        while url
          page = JSON.parse(get(url))
          lignes.concat(page.fetch("data"))
          url = page["next"]
        end
        lignes
      rescue *ERREURS_FRONTIERE => e
        raise AnalysesIndisponibles, "#{e.class} sur #{url} : #{e.message}"
      end

      # Un enregistrement par prélèvement (dédoublonné sur `code_prelevement`),
      # avec l'état de chaque conformité : true (conforme), false (non conforme)
      # ou nil (non évaluée sur ce prélèvement).
      def prelevements(code_insee, date_min)
        vus = {}
        resultats(code_insee, date_min).each do |ligne|
          code = ligne["code_prelevement"]
          date = ligne["date_prelevement"]
          next if code.blank? || date.blank? || vus.key?(code)

          vus[code] = {
            code:,
            date: Date.parse(date),
            conformites: {
              "microbiologique" => etat(ligne["conformite_limites_bact_prelevement"]),
              "physicochimique" => etat(ligne["conformite_limites_pc_prelevement"]),
              "references_qualite" => etat_references(ligne)
            }
          }
        end
        vus.values
      rescue *ERREURS_FRONTIERE => e
        raise AnalysesIndisponibles, "#{e.class} pour la commune #{code_insee} : #{e.message}"
      end

      private

      def get(url)
        reponse = Net::HTTP.get_response(URI(url))
        unless reponse.is_a?(Net::HTTPSuccess)
          raise AnalysesIndisponibles, "HTTP #{reponse.code} sur #{url}"
        end

        reponse.body
      end

      def etat(valeur)
        case valeur
        when "C" then true
        when "N" then false
        end
      end

      # Conformité aux références de qualité = conforme seulement si aucune des
      # deux composantes (bactério, physico-chimique) n'est non conforme.
      def etat_references(ligne)
        etats = [
          etat(ligne["conformite_references_bact_prelevement"]),
          etat(ligne["conformite_references_pc_prelevement"])
        ].compact
        return nil if etats.empty?

        etats.all?
      end
    end
  end
end
