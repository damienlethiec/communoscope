# Import récurrent (hebdomadaire) et idempotent des résultats du contrôle
# sanitaire de l'eau potable (API Hub'Eau) pour les communes de la métropole
# (filtre par code INSEE présent en base), puis recalcul des feux. Rejouable
# sans dégât : les conformités sont upsertées sur (commune, domaine, indicateur,
# date) — l'indicateur porte le code du prélèvement — et le feu n'est historisé
# que s'il change. Journalisé via Rails.logger et le journal Solid Queue.
#
# En production : `bin/rails eau:import` (toutes les communes) ou
# Eau::ImportJob.perform_later("69123") pour une commune.
module Eau
  class ImportJob < ApplicationJob
    queue_as :default

    # On récupère un peu plus de 12 mois pour couvrir toute la fenêtre du feu
    # même entre deux exécutions.
    FENETRE_MOIS = 13

    def perform(*codes_insee)
      communes = Commune.all.index_by(&:code_insee)
      communes = communes.slice(*codes_insee) if codes_insee.any?
      date_min = (Date.current << FENETRE_MOIS).iso8601

      erreurs = {}
      communes.each_value do |commune|
        nombre = importe_commune(commune, date_min)
        Rails.logger.info("[Eau::ImportJob] #{commune.code_insee} : #{nombre} mesures importées")
      rescue QualiteEauPotable::AnalysesIndisponibles => e
        erreurs[commune.code_insee] = e
        Rails.logger.error("[Eau::ImportJob] #{commune.code_insee} indisponible : #{e.message}")
      end

      communes.each_value { |commune| Feu.recalculer!(commune) }

      return if erreurs.empty?

      details = erreurs.map { |code, e| "#{code} (#{e.message})" }.join(", ")
      raise QualiteEauPotable::AnalysesIndisponibles, "Communes indisponibles : #{details}"
    end

    private

    def importe_commune(commune, date_min)
      source_url = QualiteEauPotable.source_url(commune.code_insee)

      lignes = QualiteEauPotable.prelevements(commune.code_insee, date_min).flat_map do |prelevement|
        prelevement[:conformites].filter_map do |type, conforme|
          next if conforme.nil?

          {
            commune_id: commune.id, domaine: Feu::DOMAINE,
            indicateur: "#{type}:#{prelevement[:code]}",
            valeur: conforme ? 1 : 0, date: prelevement[:date], source_url:
          }
        end
      end

      Measurement.upsert_all(lignes, unique_by: %i[commune_id domaine indicateur date]) if lignes.any?
      lignes.size
    end
  end
end
