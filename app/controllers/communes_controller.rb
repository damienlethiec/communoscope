class CommunesController < ApplicationController
  DOMAINES = %w[finances eau].freeze

  def index
    @feux = DOMAINES.index_with { |domaine| TrafficLight.derniers_par_commune(domaine:) }
    @couleur = params[:couleur].presence_in(TrafficLight::COULEURS)
    @domaine = params[:domaine].presence_in(DOMAINES)
    @recherche = params[:q].to_s.strip
    @communes = communes_filtrees
  end

  def show
    @commune = Commune.find_by!(code_insee: params[:code_insee])
    @historique = @commune.traffic_lights.order(id: :desc)
  end

  private

  def communes_filtrees
    communes = Commune.order(:nom).to_a
    communes.select! { |commune| feux_correspondants?(commune) } if @couleur || @domaine
    communes.select! { |commune| nom_correspondant?(commune) } if @recherche.present?
    communes
  end

  # Une commune correspond si, dans le(s) domaine(s) retenu(s), un feu existe
  # (filtre domaine seul) ou porte la couleur demandée (filtre couleur).
  def feux_correspondants?(commune)
    domaines = @domaine ? [ @domaine ] : DOMAINES
    feux = domaines.map { |domaine| @feux[domaine][commune.id] }
    if @couleur
      feux.any? { |feu| feu&.couleur == @couleur }
    else
      feux.any?(&:present?)
    end
  end

  def nom_correspondant?(commune)
    normaliser(commune.nom).include?(normaliser(@recherche))
  end

  def normaliser(chaine)
    I18n.transliterate(chaine).downcase
  end
end
