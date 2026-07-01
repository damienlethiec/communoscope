# Communoscope

Tableau de bord open data public qui évalue la gestion des communes de la
Métropole de Lyon : un feu vert / orange / rouge par domaine (finances, eau…),
calculé à partir d'indicateurs officiels et de seuils explicites, jamais de
note globale ni de jugement éditorial.

Le design complet est documenté dans [docs/design.md](docs/design.md).

## Prérequis

- Ruby (version pinnée dans `.ruby-version`, gérée avec [mise](https://mise.jdx.dev))
- SQLite 3

## Mise en route

```sh
bin/setup
```

Installe les gems, prépare la base SQLite et charge les communes de la
métropole (`bin/rails db:seed`, idempotent).

## Tests

```sh
bin/rails test
```

Lint (RuboCop, règles rails-omakase) :

```sh
bin/rubocop
```
