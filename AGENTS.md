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
ligne ; `TrafficLight.derniers_par_commune(domaine:)` rend le dernier feu de
chaque commune en une requête, indexé par `commune_id`, pour les vues liste
sans N+1, ex. l'accueil `communes#index`). Le module finances est le modèle à
suivre ; un nouveau domaine
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
  L'export CSV réel d'Opendatasoft (`/exports/csv`) commence par un BOM UTF-8
  (`EF BB BF`) : `mesures` le retire avant `CSV.parse`, sinon le premier
  en-tête devient `﻿an` et toutes les lignes sont ignorées silencieusement.
  Le fixture `comptes_individuels_bom_2023.csv` porte ce BOM pour couvrir le cas.
- Eau potable : API Hub'Eau « qualité de l'eau potable » (contrôle sanitaire
  SISE-Eaux des ARS), Licence Ouverte 2.0. Endpoint
  `/api/v1/qualite_eau_potable/resultats_dis`, filtré par `code_commune` (INSEE)
  et `date_min_prelevement`, pagination suivie via `next`. L'API rend une ligne
  par analyse (paramètre) ; les champs de conformité (`conformite_limites_bact_
  prelevement`, `..._pc_prelevement`, `conformite_references_bact/pc_prelevement`,
  « C »/« N ») sont au niveau du prélèvement, donc `Eau::QualiteEauPotable.
  prelevements` dédoublonne par `code_prelevement`. Chaque prélèvement produit
  jusqu'à 3 `measurements` (`indicateur` = `"<type>:<code_prelevement>"`,
  `valeur` 1 conforme / 0 non conforme) : `microbiologique`, `physicochimique`,
  `references_qualite`. Le feu (`Eau::Feu`) compte les non-conformités sur les
  12 mois précédant le prélèvement le plus récent (fenêtre ancrée sur la donnée,
  pas sur la date du jour, pour rester idempotent). Import production :
  `bin/rails eau:import` (toutes les communes) ou
  `Eau::ImportJob.perform_later("69123")` ; relance hebdomadaire dans
  `config/recurring.yml`. Seuils sourcés dans `config/feux/eau.yml` (arrêté du
  11 janvier 2007, CSP R.1321-2/3).
- Fixtures eau (`test/fixtures/files/eau/*.json`) : extraits réels de la réponse
  `/resultats_dis` (mêmes clés que l'API), réduits à quelques prélèvements et
  ajustés pour couvrir vert/orange/rouge. Aucun test ne touche au réseau :
  `Eau::QualiteEauPotable.resultats` (frontière HTTP) est substitué par ces
  fichiers. Pour rafraîchir un extrait : appeler l'endpoint avec `fields=` +
  `code_commune=` sur la commune voulue et retranscrire le tableau `data`.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
