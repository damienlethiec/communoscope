# Calcule le feu « finances » d'une commune à partir de ses mesures et des
# seuils versionnés dans config/feux/finances.yml. Chaque indicateur est
# calculé sur l'exercice complet le plus récent qui le rend calculable : un
# millésime aux colonnes manquantes ne peut donc pas améliorer le feu par
# simple absence de donnée (repli sur l'exercice précédent).
# Le feu du domaine est la pire couleur de ses indicateurs ; chaque feu
# enregistre sa justification chiffrée (valeurs, seuils, source, année) dans
# TrafficLight, historisé par changement.
module Finances
  class Feu
    DOMAINE = "finances"

    def self.config
      @config ||= YAML.load_file(Rails.root.join("config/feux/finances.yml"))
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
        "annee" => annee,
        "source_url" => source_url,
        "indicateurs" => indicateurs
      }
    end

    def indicateurs
      @indicateurs ||= %i[endettement autofinancement rigidite_charges].filter_map do |methode|
        exercice_calculable(methode)
      end
    end

    # Cherche, du plus récent au plus ancien, le premier exercice qui rend
    # l'indicateur calculable.
    def exercice_calculable(methode)
      exercices.each do |exercice|
        resultat = send(methode, exercice)
        return resultat if resultat
      end
      nil
    end

    def annee
      indicateurs.map { |i| i["annee"] }.max
    end

    def source_url
      exercices.find { |exercice| exercice[:annee] == annee }&.fetch(:source_url)
    end

    def endettement(exercice)
      valeurs = exercice[:valeurs]
      dette, caf, dette_hab, strate =
        valeurs.values_at("encours_dette", "caf_brute", "dette_par_habitant", "dette_par_habitant_strate")
      return nil if [ dette, caf, dette_hab, strate ].any?(&:nil?)

      capacite = if dette <= 0
        0.0
      elsif caf > 0
        (dette / caf).round(1)
      end
      ratio_strate = strate.positive? ? (dette_hab / strate).round(2) : nil
      seuils = seuils_de("endettement")
      capa_seuils = seuils.fetch("capacite_desendettement_annees")

      couleur = if capacite.nil? || capacite > capa_seuils.fetch("rouge_au_dela_de")
        "rouge"
      elsif capacite > capa_seuils.fetch("orange_au_dela_de") ||
          (ratio_strate && ratio_strate > seuils.dig("ratio_dette_habitant_strate", "orange_au_dela_de"))
        "orange"
      else
        "vert"
      end

      indicateur("endettement", couleur, exercice,
        "capacite_desendettement_annees" => capacite,
        "ratio_dette_habitant_strate" => ratio_strate,
        "dette_par_habitant" => dette_hab,
        "dette_par_habitant_strate" => strate,
        "encours_dette" => dette,
        "caf_brute" => caf)
    end

    def autofinancement(exercice)
      valeurs = exercice[:valeurs]
      caf, prod, caf_hab, caf_strate =
        valeurs.values_at("caf_brute", "produits_fonctionnement", "caf_par_habitant", "caf_par_habitant_strate")
      return nil if caf.nil? || prod.nil? || !prod.positive?

      taux = (caf / prod * 100).round(1)
      seuils = seuils_de("autofinancement").fetch("taux_caf_brute_pct")

      couleur = if taux < seuils.fetch("rouge_en_dessous_de")
        "rouge"
      elsif taux < seuils.fetch("orange_en_dessous_de")
        "orange"
      else
        "vert"
      end

      indicateur("autofinancement", couleur, exercice,
        "taux_caf_brute_pct" => taux,
        "caf_brute" => caf,
        "produits_fonctionnement" => prod,
        "caf_par_habitant" => caf_hab,
        "caf_par_habitant_strate" => caf_strate)
    end

    def rigidite_charges(exercice)
      valeurs = exercice[:valeurs]
      perso, cont, fin, prod =
        valeurs.values_at("charges_personnel", "contingents", "charges_financieres", "produits_fonctionnement")
      return nil if [ perso, cont, fin, prod ].any?(&:nil?) || !prod.positive?

      taux = ((perso + cont + fin) / prod * 100).round(1)
      seuils = seuils_de("rigidite_charges").fetch("rigidite_pct")

      couleur = if taux > seuils.fetch("rouge_au_dela_de")
        "rouge"
      elsif taux > seuils.fetch("orange_au_dela_de")
        "orange"
      else
        "vert"
      end

      indicateur("rigidite_charges", couleur, exercice,
        "rigidite_pct" => taux,
        "charges_personnel" => perso,
        "contingents" => cont,
        "charges_financieres" => fin,
        "produits_fonctionnement" => prod)
    end

    def indicateur(nom, couleur, exercice, valeurs)
      config = self.class.config.dig("indicateurs", nom)
      {
        "indicateur" => nom,
        "libelle" => config.fetch("libelle"),
        "annee" => exercice[:annee],
        "couleur" => couleur,
        "valeurs" => valeurs,
        "seuils" => config.fetch("seuils")
      }
    end

    def seuils_de(nom)
      self.class.config.dig("indicateurs", nom, "seuils")
    end

    # Exercices de la commune, du plus récent au plus ancien, chacun portant
    # ses valeurs (indicateur → montant) et sa source.
    def exercices
      @exercices ||= mesures
        .pluck(:date, :indicateur, :valeur, :source_url)
        .group_by(&:first)
        .map do |date, lignes|
          {
            annee: date.year,
            source_url: lignes.first[3],
            valeurs: lignes.to_h { |ligne| [ ligne[1], ligne[2].to_f ] }
          }
        end
        .sort_by { |exercice| -exercice[:annee] }
    end

    def mesures
      @commune.measurements.where(domaine: DOMAINE)
    end
  end
end
