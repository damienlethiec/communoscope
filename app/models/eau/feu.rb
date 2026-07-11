# Calcule le feu « eau potable » d'une commune à partir de ses mesures de
# conformité (une par prélèvement × type, stockées dans measurements) et des
# seuils versionnés dans config/feux/eau.yml.
#
# Base de calcul : les prélèvements des 12 derniers mois. La fenêtre est ancrée
# sur le prélèvement le plus récent disponible pour la commune (et non sur la
# date du jour), afin que le calcul soit déterministe et idempotent : rejouer
# le feu sans nouvelle donnée ne change rien.
#
# Chaque indicateur (microbiologique, physico-chimique, références de qualité)
# compte ses prélèvements non conformes sur la fenêtre ; le feu du domaine est
# la pire couleur de ses indicateurs. La justification chiffrée (période,
# nombres, seuils, source) est historisée dans TrafficLight par changement.
module Eau
  class Feu
    DOMAINE = "eau"
    TYPES = %w[microbiologique physicochimique references_qualite].freeze

    def self.config
      @config ||= YAML.load_file(Rails.root.join("config/feux/eau.yml"))
    end

    def self.recalculer!(commune)
      new(commune).recalculer!
    end

    def initialize(commune)
      @commune = commune
    end

    def recalculer!
      return nil if indicateurs.empty?

      TrafficLight.enregistrer!(commune: @commune, domaine: DOMAINE, couleur:, justification:)
    end

    private

    def couleur
      TrafficLight::COULEURS.reverse.find { |c| indicateurs.any? { |i| i["couleur"] == c } }
    end

    def justification
      {
        "periode_debut" => fenetre_debut.iso8601,
        "periode_fin" => fenetre_fin.iso8601,
        "source_url" => source_url,
        "indicateurs" => indicateurs
      }
    end

    def indicateurs
      @indicateurs ||= TYPES.filter_map { |type| indicateur(type) }
    end

    def indicateur(type)
      mesures = mesures_fenetre.select { |m| m.indicateur.start_with?("#{type}:") }
      return nil if mesures.empty?

      non_conformes = mesures.count { |m| m.valeur.zero? }
      config = self.class.config.dig("indicateurs", type)
      seuils = config.fetch("seuils").fetch("non_conformites_12_mois")

      {
        "indicateur" => type,
        "libelle" => config.fetch("libelle"),
        "couleur" => couleur_indicateur(non_conformes, seuils),
        "valeurs" => {
          "prelevements_evalues" => mesures.size,
          "prelevements_non_conformes" => non_conformes
        },
        "seuils" => config.fetch("seuils")
      }
    end

    def couleur_indicateur(non_conformes, seuils)
      rouge = seuils["rouge_a_partir_de"]
      if rouge && non_conformes >= rouge
        "rouge"
      elsif non_conformes >= seuils.fetch("orange_a_partir_de")
        "orange"
      else
        "vert"
      end
    end

    def source_url
      mesures_fenetre.first&.source_url
    end

    # Prélèvements des 12 mois précédant le prélèvement le plus récent.
    def mesures_fenetre
      @mesures_fenetre ||= mesures.select { |m| m.date >= fenetre_debut }
    end

    def fenetre_fin
      @fenetre_fin ||= mesures.map(&:date).max
    end

    def fenetre_debut
      @fenetre_debut ||= fenetre_fin << 12
    end

    def mesures
      @mesures ||= @commune.measurements.where(domaine: DOMAINE).to_a
    end
  end
end
