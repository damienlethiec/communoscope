class Measurement < ApplicationRecord
  belongs_to :commune

  validates :domaine, :indicateur, :date, :source_url, presence: true
  validates :valeur, presence: true, numericality: true
  validates :indicateur, uniqueness: { scope: [ :commune_id, :domaine, :date ] }
end
