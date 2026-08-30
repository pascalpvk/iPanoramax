# iPanoramax

Client iOS natif pour [Panoramax](https://panoramax.fr), le commun numérique de
photo-cartographie porté par l'IGN, OpenStreetMap France et le Ministère de la
Transition écologique.

Capture de photos géolocalisées — séquence le long d'une route ou d'un chemin,
cliché unique, panoramique circulaire guidé — et publication sur l'instance
Panoramax de votre choix.

> **État du projet : phase 0, fondations.** Rien n'est encore utilisable.
> Voir la [feuille de route](#feuille-de-route).

## Pourquoi un client natif

Une [application mobile Panoramax officielle](https://gitlab.com/panoramax/clients/mobile-app)
existe déjà, écrite en Flutter et publiée sur l'App Store par l'IGN. iPanoramax
ne cherche pas à la remplacer, mais à explorer ce qu'un client **entièrement
natif** permet de mieux faire :

- pilotage fin d'`AVFoundation` — cadence de déclenchement, exposition,
  stabilisation, capture JPEG sans ré-encodage ;
- envoi en tâche de fond via `URLSession` background, avec reprise automatique ;
- fusion GPS / boussole / centrale inertielle (`CoreLocation` + `CoreMotion`)
  pour un cap fiable aussi bien à pied qu'en véhicule.

C'est là que se joue la qualité d'une séquence.

## Architecture

Quatre couches, et une règle : **tout ce qui n'a pas besoin d'UIKit n'en dépend
pas**. Les modules d'infrastructure sont des Swift Packages purs, testables en
CI sans simulateur.

```
Application    iPanoramaxApp · navigation · réglages · onboarding
      ↓
Features       Capture · Library · Upload UI · Map · Account
      ↓
Domaine        CaptureSession · Shot · Instance · UploadJob · CaptureTrigger
      ↓
Infrastructure PanoramaxKit · ImageMetadataKit · GeoKit
               UploadEngine · Persistence · DesignSystem
```

| Module | Rôle |
|---|---|
| `PanoramaxKit` | Client de l'API Panoramax (STAC API 1.0.0 + extensions) |
| `ImageMetadataKit` | Écriture EXIF et injection XMP dans le JPEG |
| `GeoKit` | `CoreLocation`, `CoreMotion`, logique de déclenchement |
| `UploadEngine` | File d'envoi persistée, session background, reprises |
| `Persistence` | SwiftData : sessions, clichés, tâches d'envoi |
| `DesignSystem` | Jetons, composants, mode capture |

L'étude complète — API Panoramax, contraintes iOS, décisions d'architecture —
est dans [`docs/`](docs/).

## Démarrer

```bash
git clone https://github.com/pascalpvk/iPanoramax.git
cd iPanoramax

# Tester le client d'API, sans Xcode ni simulateur
cd Packages/PanoramaxKit && swift test

# Générer le projet Xcode (le .xcodeproj n'est pas versionné)
brew install xcodegen swiftlint
xcodegen generate --spec App/project.yml
open App/iPanoramax.xcodeproj
```

Prérequis : Xcode 16 ou plus récent, iOS 17 minimum, Swift 6 en concurrence
stricte.

### Instance de développement

Pour ne pas polluer les instances publiques pendant le développement, lancez une
instance Panoramax locale :

```bash
git clone https://gitlab.com/panoramax/server/api.git panoramax-api
cd panoramax-api && docker compose up
```

## Authentification

Panoramax se prête bien au mobile : le flux « generate & claim » ne demande
aucune inscription préalable de l'application côté serveur, ce qui permet à
iPanoramax de fonctionner sur **n'importe laquelle** des instances publiques.

```swift
let client = PanoramaxClient(instance: .openStreetMapFrance)

// 1. Générer un jeton non revendiqué
let token = try await client.generateToken(description: "iPanoramax sur iPhone de Pascal")

// 2. Faire ouvrir token.claimURL par l'utilisateur (ASWebAuthenticationSession)

// 3. Attendre la revendication
let user = try await client.waitForTokenClaim()
```

## Envoi

```swift
let uploadSet = try await client.createUploadSet(
    UploadSetRequest(title: "Chemin des Vignes", estimatedNbFiles: 214)
)

let (request, bodyURL) = try await client.makeUploadRequest(
    uploadSetID: uploadSet.id,
    pictureID: shot.id,          // généré à la capture → envoi idempotent
    jpegURL: shot.fileURL,
    bodyDirectory: uploadsDirectory
)
backgroundSession.uploadTask(with: request, fromFile: bodyURL).resume()

try await client.completeUploadSet(id: uploadSet.id)
```

Le `picture_id` est généré **à la capture**, pas à l'envoi : le POST devient
idempotent, et une coupure réseau se rejoue sans créer de doublon.

## Feuille de route

| Phase | Objet | Livrable |
|---|---|---|
| 0 | Fondations, CI, `PanoramaxKit` (config + auth) | Un jeton obtenu depuis une démo minimale |
| 1 | `ImageMetadataKit` — EXIF et XMP | Photo fabriquée par le code, acceptée à l'ingestion |
| 2 | Capture de séquence | 500 m à pied → séquence propre |
| 3 | Envoi fiable en tâche de fond | 200 photos envoyées, app en arrière-plan |
| 4 | Carte MapLibre et multi-instances | Bascule OSM-FR ↔ IGN |
| 5 | Photo unique et panoramique guidé | Un tour complet visible sur la carte |
| 6 | Localisation, accessibilité, App Store | Soumission |

## Licences

Le **code** est sous [licence MIT](LICENSE), comme le serveur d'API, la
visionneuse web et le CLI Panoramax.

Les **photos** que vous publiez relèvent de la licence de l'instance choisie —
Licence Ouverte 2.0 (Etalab) pour l'IGN, CC-BY-SA 4.0 pour OpenStreetMap France.
L'application affiche cette licence et la couverture géographique acceptée avant
tout envoi.

Le floutage des visages et des plaques d'immatriculation est effectué **par le
serveur**. Sur les instances où il est activé, l'original non flouté n'est pas
conservé.

## Contribuer

Voir [CONTRIBUTING.md](CONTRIBUTING.md). Le projet suit le
[Contributor Covenant 2.1](CODE_OF_CONDUCT.md), comme l'ensemble des dépôts
Panoramax.

---

Projet indépendant, sans affiliation avec l'IGN ni avec l'association
OpenStreetMap France. « Panoramax » est une marque du projet Panoramax.
