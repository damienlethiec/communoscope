class CommunesController < ApplicationController
  def index
    @communes = Commune.order(:nom)
    @feux_finances = TrafficLight.derniers_par_commune(domaine: "finances")
  end
end
