namespace :finances do
  desc "Importe les comptes individuels DGFiP (backfill des millésimes connus) et recalcule les feux"
  task import: :environment do
    Finances::ImportJob.perform_now
  end
end
