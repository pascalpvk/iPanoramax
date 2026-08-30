# Notes sur l'API Panoramax

Relevé de terrain, à jour au 30 août 2026. Sources : documentation officielle
(`docs.panoramax.fr/backend/`) et spécification OpenAPI servie par les instances
(`/api/docs/specs.json`).

L'API est une **STAC API 1.0.0** (SpatioTemporal Asset Catalog) bâtie sur
OGC API — Features, augmentée d'extensions Panoramax.

| Terme STAC | Signification Panoramax |
|---|---|
| Collection | une séquence de photos |
| Item | une photo, avec géométrie et propriétés |
| Asset | les fichiers rattachés : original, vignette, tuiles pour les 360° |

Extensions Panoramax : propriétés `geovisio:*`, `datetimetz`,
`quality:horizontal_accuracy`, `original_file:*`, objet `semantics` pour les
annotations clé/valeur, et permissions HATEOAS (`edit`, `delete`, `add_files`,
`complete`) renvoyées sur chaque ressource identifiée.

## Authentification

Deux mécanismes : OAuth2 navigateur (OSM pour l'instance OSM-FR, Keycloak pour
l'IGN) et jetons JWT porteurs. **Seul le second convient à une app mobile.**

```
POST /api/auth/tokens/generate          # aucune authentification requise
  → { id, jwt_token, generated_at, links: [{ rel: "claim", href }] }

<ouvrir href dans ASWebAuthenticationSession>

GET  /api/users/me   Authorization: Bearer <jwt_token>
  → 200 = revendiqué et valide · 401 = pas encore revendiqué

DELETE /api/users/me/tokens/<uuid>      # révocation
```

L'intérêt décisif : **aucune inscription préalable de l'application** n'est
nécessaire auprès de chaque instance. Le même code fonctionne sur la vingtaine
d'instances publiques.

Stockage du JWT : Keychain, avec `kSecAttrAccessibleAfterFirstUnlock` — il doit
rester lisible par la session d'envoi en tâche de fond, qui peut s'exécuter
appareil verrouillé.

## Envoi — *upload sets*

Voir [ADR 0001](adr/0001-upload-sets-plutot-que-collections.md) pour le choix
entre les deux API d'envoi.

### 1. Créer

```
POST /api/upload_sets            Content-Type: application/json
```

| Champ | Type | Défaut |
|---|---|---|
| `title` | chaîne | **requis** |
| `estimated_nb_files` | entier | — |
| `split_distance` | entier (m) | instance (100) |
| `split_time` | nombre (s) | instance (300) |
| `no_split` | booléen | `false` |
| `duplicate_distance` | nombre (m) | instance (1.0) |
| `duplicate_rotation` | entier (°) | instance (60) |
| `no_deduplication` | booléen | `false` |
| `sort_method` | `filename-asc` \| `filename-desc` \| `time-asc` \| `time-desc` | — |
| `visibility` | `anyone` \| `owner-only` \| `logged-only` | instance |
| `relative_heading` | entier (°) | — |
| `metadata` | objet | — |
| `semantics` | tableau clé/valeur | — |
| `user_agent` | chaîne | — |

Réponse : `201`, en-tête `Location`, et l'UUID dans le corps.

### 2. Verser les fichiers

```
POST /api/upload_sets/{id}/files       multipart/form-data
```

| Champ | Notes |
|---|---|
| `file` | **requis**, JPEG |
| `picture_id` | UUID fourni par le client → **envoi idempotent** |
| `override_capture_time` | ISO 8601 |
| `override_latitude` / `override_longitude` | degrés décimaux WGS84 |
| `isBlurred` | `true` \| `false` |
| `override_Exif.*` / `override_Xmp.*` | surcharge de tags |

Les noms de fichier doivent être uniques au sein de l'ensemble. Un fichier
invalide est rejeté mais compte dans le total attendu.

### 3. Clore

```
POST /api/upload_sets/{id}/complete
```

Nécessaire dès que le nombre réel diffère de `estimated_nb_files` — donc en
pratique toujours, puisque l'utilisateur peut supprimer des clichés.

### 4. Suivre

```
GET /api/upload_sets/{id}
  → { completed, dispatched, ready,
      items_status: { prepared, preparing, broken, rejected, not_processed },
      associated_collections: [...] }

GET /api/upload_sets/{id}/files
  → par fichier : rejected { reason, severity, message, details }
```

Le traitement est asynchrone : découpage en séquences, déduplication, floutage,
génération des dérivés.

## Configuration d'instance

`GET /api/configuration` — à lire avant tout envoi. Porte la licence des photos,
la couverture géographique acceptée, les valeurs de découpage par défaut, et
l'identité visuelle de l'instance. Voir la fixture
`Packages/PanoramaxKit/Tests/PanoramaxKitTests/Fixtures/configuration-ign.json`
pour un exemple réel.

## Carte

`/api/map/…` sert un style MapLibre. Couches : `geovisio_grid`,
`geovisio_sequences`, `geovisio_pictures`. Aucune clé d'API tierce nécessaire.

## Recherche

`GET|POST /api/search`, filtrage CQL2. À noter : Panoramax n'implémente pas
`numberMatched` ni `numberReturned` — la pagination se fait par les liens
`next` / `prev`.

## Floutage

Effectué **côté serveur** par un service externe configuré par l'instance
(`API_BLUR_URL`, par exemple SGBlur). Sur une instance où il est activé,
l'original non flouté n'est pas conservé. Le client n'a rien à flouter, mais
doit l'expliquer à l'utilisateur.

## Instances principales

| Instance | API | Licence des photos | Couverture |
|---|---|---|---|
| OpenStreetMap France | `panoramax.openstreetmap.fr` | CC-BY-SA 4.0 | monde, France privilégiée |
| IGN | `panoramax.ign.fr` | Licence Ouverte 2.0 | France uniquement, hors zones sensibles |
| autres (~20) | listées sur `api.panoramax.xyz` | CC-BY-SA ou compatible | régionales |

## Écosystème et licences

| Composant | Licence |
|---|---|
| Server / API (Python, PostGIS) | MIT |
| Web viewer (JavaScript) | MIT |
| CLI (`panoramax_cli`) | MIT |
| Meta-catalog | MIT |
| Mobile app (Flutter) | AGPL-3.0 |
