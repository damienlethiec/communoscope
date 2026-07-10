class Commune < ApplicationRecord
  has_many :measurements, dependent: :destroy
  has_many :traffic_lights, dependent: :destroy

  validates :code_insee, presence: true, uniqueness: true
  validates :nom, presence: true

  def feu(domaine)
    TrafficLight.dernier(commune: self, domaine:)
  end
end
