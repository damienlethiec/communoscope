# Communoscope — Design v1

Date : 2026-07-01 · Statut : validé en discussion, en attente de relecture finale du captain
Repo : https://github.com/damienlethiec/communoscope (public, mode no-mistakes)

## But

Permettre de voir **en un coup d'œil** si une commune de la métropole de Lyon est bien
gérée sur des critères factuels et sourcés, et de **fouiller le détail** derrière chaque
signal. Pas de jugement éditorial : des indicateurs officiels, des seuils explicites.

## Périmètre v1

- Les communes de la **métropole de Lyon** (58 selon geo.api.gouv.fr, liste par code INSEE).
- Deux domaines d'indicateurs : **finances communales** et **eau potable**.
- Un **feu vert / orange / rouge par domaine et par commune**, jamais de note globale.
- Un bandeau **« quoi de neuf »** listant les derniers changements de feux.
- **Pas de comptes, pas d'alertes** (v2), pas de carte interactive obligatoire (une grille suffit).

Hors périmètre v1 (backlog v2+) : qualité de l'air (ATMO AuRA), transparence des achats
(DECP), qualité des sols (BASOL/InfoSols), alertes email, abonnement public par commune.
Écarté sauf décision contraire : condamnations d'élus (pas de source officielle propre,
risque juridique).

## Architecture

Monolithe **Rails 8** : SQLite en production, **Solid Queue** pour les jobs récurrents
d'ingestion, **Hotwire** pour l'UI, Tailwind CSS. Déploiement **Kamal** sur une instance
**Scaleway** (compte existant ; non bloquant pour démarrer).

Principe central : chaque domaine est un **module enfichable** respectant le même contrat :

1. une **source** open data documentée ;
2. un **job d'ingestion** idempotent et journalisé ;
3. un **calcul de feu** à partir de seuils explicites ;
4. une **section de fiche** commune (partial + explication du feu).

Ajouter un domaine (air, achats, sols…) = ajouter un module, sans toucher au reste.

## Modèle de données

- `communes` — les communes de la métropole ; clé naturelle : code INSEE ; nom, population.
- `measurements` — valeurs brutes datées : commune, domaine, indicateur, valeur, date,
  URL/référence de la source. Append-only, réimport sans doublon (idempotence).
- `traffic_lights` — le feu calculé par commune × domaine, **historisé** (une ligne par
  changement, avec la justification). L'historique nourrit le « quoi de neuf » en v1 et
  les alertes en v2.

## Ingestion

- **Finances** : comptes individuels des communes (DGFiP, data.gouv.fr, un fichier
  annuel par millésime). Réimport mensuel idempotent (pour récupérer les corrections
  et les nouveaux millésimes) + backfill de plusieurs années pour les tendances.
- **Eau potable** : API Hub'Eau « qualité de l'eau potable » (SISE-Eaux). Rafraîchissement
  hebdomadaire.
- Jobs Solid Queue récurrents, idempotents, rejouables sans dégât, avec journal d'exécution.

## Feux et seuils

Seuils **explicites, versionnés et sourcés** dans un fichier YAML du repo — jamais de boîte
noire. Chaque feu affiche sa justification chiffrée et le lien vers la source.

- **Finances** : ratios officiels comparés à la strate démographique — endettement
  (dette/habitant, capacité de désendettement), capacité d'autofinancement, rigidité des
  charges. Vert = dans les clous de la strate ; orange = au-delà d'un premier seuil ;
  rouge = zone d'alerte reconnue (ex. capacité de désendettement > 12 ans).
- **Eau** : conformité microbiologique et physico-chimique des analyses des 12 derniers
  mois. Vert = conforme ; orange = non-conformités ponctuelles sans restriction d'usage ;
  rouge = non-conformité avec restriction ou récurrente.

Les seuils précis sont affinés par l'équipage lors de l'implémentation de chaque module,
avec référence réglementaire à l'appui, et soumis à relecture dans la PR.

## UI

- **Accueil** : grille des communes avec leurs feux, recherche/tri, bandeau « quoi de neuf ».
- **Fiche commune** : les domaines, l'explication de chaque feu (chiffres, seuils, sources),
  l'historique des changements.
- Sobre, lisible, mobile-friendly. Tailwind, pas de framework JS lourd.

## Qualité

- TDD, minitest (voie Rails standard).
- Réponses d'API fixturées (VCR ou fixtures maison) pour des tests reproductibles.
- CI GitHub Actions ; chaque livraison passe le pipeline de validation avant PR.

## Séquencement prévu (chaque étape = une livraison)

1. Socle Rails 8 (app, CI, Tailwind, modèle `communes` + seed des communes de la métropole).
2. Module finances : ingestion DGFiP + calcul des feux.
3. Module eau : ingestion Hub'Eau + calcul des feux.
4. Fiches communes + accueil (grille, recherche).
5. « Quoi de neuf » (historique des feux).
6. Déploiement Kamal sur Scaleway.
