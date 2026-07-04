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
end
