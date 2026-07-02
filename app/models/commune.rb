class Commune < ApplicationRecord
  validates :code_insee, presence: true, uniqueness: true
  validates :nom, presence: true
end
