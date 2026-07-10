# Import récurrent et idempotent des comptes individuels DGFiP pour les
# communes de la métropole (filtre par code INSEE présent en base), puis
# recalcul des feux. Rejouable sans dégât : les mesures sont upsertées sur
# (commune, domaine, indicateur, date) et le feu n'est historisé que s'il
# change. Journalisé via Rails.logger et le journal Solid Queue.
#
# En production : `bin/rails finances:import` (backfill complet) ou
# Finances::ImportJob.perform_later(2024) pour un seul millésime.
module Finances
  class ImportJob < ApplicationJob
    queue_as :default

    def perform(*annees)
      annees = ComptesIndividuels::ANNEES if annees.empty?
      communes = Commune.all.index_by(&:code_insee)

      erreurs = {}
      annees.each do |annee|
        nombre = importe_annee(annee, communes)
        Rails.logger.info("[Finances::ImportJob] #{annee} : #{nombre} mesures importées")
      rescue ComptesIndividuels::ExportIndisponible => e
        erreurs[annee] = e
        Rails.logger.error("[Finances::ImportJob] #{annee} indisponible : #{e.message}")
      end

      communes.each_value { |commune| Feu.recalculer!(commune) }

      return if erreurs.empty?

      details = erreurs.map { |annee, e| "#{annee} (#{e.message})" }.join(", ")
      raise ComptesIndividuels::ExportIndisponible, "Millésimes indisponibles : #{details}"
    end

    private

    def importe_annee(annee, communes)
      date = Date.new(annee, 12, 31)
      source_url = ComptesIndividuels.source_url(annee)

      lignes = ComptesIndividuels.mesures(annee).filter_map do |mesure|
        commune = communes[mesure[:code_insee]]
        next unless commune

        mesure[:valeurs].map do |indicateur, valeur|
          { commune_id: commune.id, domaine: Feu::DOMAINE, indicateur:, valeur:, date:, source_url: }
        end
      end.flatten

      Measurement.upsert_all(lignes, unique_by: %i[commune_id domaine indicateur date]) if lignes.any?
      lignes.size
    end
  end
end
