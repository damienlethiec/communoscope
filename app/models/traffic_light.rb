class TrafficLight < ApplicationRecord
  COULEURS = %w[vert orange rouge].freeze

  belongs_to :commune

  validates :domaine, :justification, :date, presence: true
  validates :couleur, inclusion: { in: COULEURS }

  # Historisation : une ligne par changement de feu. Rejouer un calcul dont les
  # entrées n'ont pas changé ne crée pas de ligne.
  def self.enregistrer!(commune:, domaine:, couleur:, justification:, date: Date.current)
    dernier = dernier(commune:, domaine:)
    if dernier && dernier.couleur == couleur && dernier.justification == justification.as_json
      return dernier
    end

    create!(commune:, domaine:, couleur:, justification: justification.as_json, date:)
  end

  def self.dernier(commune:, domaine:)
    where(commune:, domaine:).order(:id).last
  end

  # Dernier feu de chaque commune pour un domaine, en une seule requête
  # (évite le N+1 quand on affiche beaucoup de communes). Indexé par commune_id.
  def self.derniers_par_commune(domaine:)
    derniers_ids = where(domaine:).group(:commune_id).select("MAX(id)")
    where(id: derniers_ids).index_by(&:commune_id)
  end
end
