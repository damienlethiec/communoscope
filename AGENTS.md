# AGENTS.md

Repères pour travailler sur Communoscope. Le produit et l'architecture cible
sont décrits dans `docs/design.md` — le lire avant toute feature.

## Stack

- Rails 8.1, Ruby pinné dans `.ruby-version` (géré via mise).
- SQLite partout (dev, test, prod), Solid Queue / Solid Cache / Solid Cable.
- Hotwire (Turbo + Stimulus via importmap), Tailwind CSS. Pas de framework JS lourd.
- Défauts Rails (omakase) partout ; pas de gem supplémentaire sans besoin avéré.
- Pas de credentials chiffrés pour l'instant : `config/master.key` n'est pas
  généré (dev/test utilisent le secret local auto-généré). `bin/rails
  credentials:edit` le recréera si un secret devient nécessaire.

## Build / test

- Setup : `bin/setup` (bundle, db:prepare, seeds), puis lance `bin/dev`
  (serveur + watcher Tailwind) sauf avec `--skip-server`.
- Tests : `bin/rails test` (minitest, fixtures). Système : `bin/rails test:system`.
- Lint : `bin/rubocop` (rubocop-rails-omakase, zéro offense exigé).
- Pipeline complet en local : `bin/ci` (défini dans `config/ci.rb` : setup,
  rubocop, bundler-audit, importmap audit, brakeman, tests, seeds).
- CI GitHub Actions (`.github/workflows/ci.yml`, workflow Rails par défaut) :
  brakeman, bundler-audit, importmap audit, rubocop, tests, tests système —
  sur chaque PR et push sur `main`.

## Conventions

- TDD : écrire le test minitest d'abord, puis l'implémentation.
- The Rails Way : convention plutôt que configuration, modèles riches,
  contrôleurs minces, pas d'extraction prématurée.
- Contraintes d'intégrité en base (`null: false`, index uniques) doublées de
  validations ActiveRecord.
- Architecture module-par-domaine (cf. design) : chaque domaine d'indicateurs
  (finances, eau…) fournit source documentée, job d'ingestion idempotent,
  calcul de feu à seuils explicites (YAML versionné), et partial de fiche.
  Ajouter un domaine ne doit rien toucher au reste.

## Données

- `db/seeds/communes_metropole_lyon.json` : liste versionnée des 58 communes
  de la Métropole de Lyon (EPCI 200046977), exportée de geo.api.gouv.fr
  (`/epcis/200046977/communes?fields=code,nom,population`). `bin/rails
  db:seed` la charge sans réseau et est idempotent (upsert par code INSEE).
  Pour rafraîchir la liste : re-exporter l'URL ci-dessus, trier par code,
  committer le JSON.
