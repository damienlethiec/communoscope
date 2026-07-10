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
  (serveur + watcher Tailwind) sauf avec `--skip-server` ; `--reset` recrée
  la base avant les seeds.
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

## Contrat de module (ajouter un domaine)

Le socle partagé est agnostique du domaine : `measurements` (valeurs brutes
datées, append-only, index unique commune × domaine × indicateur × date,
réimport idempotent par upsert) et `traffic_lights` (feu historisé : une ligne
par changement via `TrafficLight.enregistrer!`, qui ne crée rien si couleur et
justification sont inchangées ; `commune.feu("domaine")` rend la dernière
ligne). Le module finances est le modèle à suivre ; un nouveau domaine
(ex. eau) ajoute, sans toucher au reste :

1. **Source** : `app/models/<domaine>/...` documentant jeu de données, URL,
   licence (cf. `Finances::ComptesIndividuels`).
2. **Job d'ingestion** : `app/jobs/<domaine>/import_job.rb`, idempotent
   (upsert des `measurements`), journalisé (`Rails.logger` + journal Solid
   Queue), planifié dans `config/recurring.yml`, avec backfill rejouable.
   Tests sur des extraits fixtures committés, aucun réseau en test.
3. **Feu** : `app/models/<domaine>/feu.rb` + seuils explicites et sourcés dans
   `config/feux/<domaine>.yml` (chaque seuil porte sa référence
   réglementaire/officielle). Le feu du domaine = pire couleur de ses
   indicateurs ; la justification chiffrée (année, valeurs, seuils, source)
   est enregistrée dans `traffic_lights`.
4. **Fiche** : partial `app/views/<domaine>/_fiche_section.html.erb`
   (local `commune:`) rendant le feu et son explication.

## Données

- `db/seeds/communes_metropole_lyon.json` : liste versionnée des 58 communes
  de la Métropole de Lyon (EPCI 200046977), exportée de geo.api.gouv.fr
  (`/epcis/200046977/communes?fields=code,nom,population`). `bin/rails
  db:seed` la charge sans réseau et est idempotent (upsert par code INSEE).
  Pour rafraîchir la liste : re-exporter l'URL ci-dessus, trier par code,
  committer le JSON.
- Finances : « Comptes individuels des communes (fichier global) », données
  DGFiP publiées par les Ministères économiques et financiers sur data.gouv.fr
  (Licence Ouverte v2.0), un jeu de données par millésime, servies par l'API
  Opendatasoft de data.economie.gouv.fr. Montants en k€, colonnes `fXXX` en
  €/habitant, `mXXX` = moyenne de la strate. Import en production :
  `bin/rails finances:import` (backfill des millésimes de
  `Finances::ComptesIndividuels::DATASETS`) ou
  `Finances::ImportJob.perform_later(2024)` ; relance mensuelle planifiée dans
  `config/recurring.yml`. Un nouveau millésime = une entrée dans `DATASETS`.
- Fixtures finances (`test/fixtures/files/finances/comptes_individuels_*.csv`) :
  extraits réels métropole-only (4 communes) du fichier DGFiP, obtenus via
  l'API records (mêmes colonnes que `Finances::ComptesIndividuels.export_url`),
  ex. `.../records?where=dep="069" and icom in ("123","266","029","091") and
  an="2023"&select=an,dep,icom,inom,pop1,prod,perso,cont,fin,caf,dette,fdette,mdette,fcaf,mcaf`
  sur le dataset du millésime, retranscrits en CSV `;`. Aucun test ne touche
  au réseau : `Finances::ComptesIndividuels.csv` est substitué par ces fichiers.
