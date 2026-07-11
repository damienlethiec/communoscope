namespace :eau do
  desc "Importe les résultats du contrôle sanitaire de l'eau potable (Hub'Eau) et recalcule les feux"
  task import: :environment do
    Eau::ImportJob.perform_now
  end
end
