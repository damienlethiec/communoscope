module FeuxHelper
  BADGES = {
    "vert" => "bg-green-100 text-green-800",
    "orange" => "bg-orange-100 text-orange-800",
    "rouge" => "bg-red-100 text-red-800"
  }.freeze

  LIBELLES_VALEURS = {
    "capacite_desendettement_annees" => "Capacité de désendettement (années)",
    "ratio_dette_habitant_strate" => "Dette/habitant rapportée à la strate",
    "dette_par_habitant" => "Dette par habitant (€)",
    "dette_par_habitant_strate" => "Dette par habitant, moyenne de la strate (€)",
    "encours_dette" => "Encours de dette (k€)",
    "caf_brute" => "CAF brute (k€)",
    "produits_fonctionnement" => "Produits de fonctionnement (k€)",
    "taux_caf_brute_pct" => "Taux de CAF brute (%)",
    "caf_par_habitant" => "CAF par habitant (€)",
    "caf_par_habitant_strate" => "CAF par habitant, moyenne de la strate (€)",
    "rigidite_pct" => "Rigidité des charges (%)",
    "charges_personnel" => "Charges de personnel (k€)",
    "contingents" => "Contingents (k€)",
    "charges_financieres" => "Charges financières (k€)",
    "prelevements_evalues" => "Prélèvements évalués (12 mois)",
    "prelevements_non_conformes" => "Prélèvements non conformes"
  }.freeze

  # État neutre inclus : classes, icône et libellé quand la couleur est absente.
  NEUTRE = { classes: "bg-gray-100 text-gray-600", icone: "–", libelle: "Non calculé" }.freeze

  ICONES = { "vert" => "✓", "orange" => "!", "rouge" => "✕" }.freeze

  def badge_feu(couleur)
    tag.span(couleur, class: "inline-block rounded-full px-2 py-0.5 text-xs font-semibold uppercase #{BADGES.fetch(couleur)}")
  end

  # Indicateur de feu pour une carte, robuste au feu nil. L'état est porté par
  # l'icône et le libellé (pas seulement la couleur) pour l'accessibilité.
  def badge_feu_carte(feu)
    couleur = feu&.couleur
    classes = couleur ? BADGES.fetch(couleur) : NEUTRE[:classes]
    icone = couleur ? ICONES.fetch(couleur) : NEUTRE[:icone]
    libelle = couleur ? couleur.capitalize : NEUTRE[:libelle]

    tag.span(class: "inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold #{classes}") do
      safe_join([ tag.span(icone, "aria-hidden": true), libelle ], " ")
    end
  end

  def libelle_valeur(cle)
    LIBELLES_VALEURS.fetch(cle, cle.humanize)
  end

  def valeur_feu(valeur)
    number_with_precision(valeur, precision: 2, strip_insignificant_zeros: true, delimiter: " ", separator: ",")
  end
end
