# Correspondance métadonnées : capteurs iOS → EXIF/XMP → Panoramax

Panoramax lit les métadonnées **dans le fichier JPEG**. Les paramètres HTTP
`override_*` de l'API ne sont qu'un filet de sécurité, pas le canal nominal :
une photo dont l'EXIF est incomplet est rejetée à l'ingestion.

Ce document est le contrat entre `GeoKit` (qui produit les mesures) et
`ImageMetadataKit` (qui les écrit). Toute évolution ici doit s'accompagner d'un
test dans `ImageMetadataKitTests`.

## Obligatoire

| Donnée | Tag EXIF | Type | Source iOS | Notes |
|---|---|---|---|---|
| Latitude | `GPSLatitude` + `GPSLatitudeRef` | rationnel D/M/S + `N`/`S` | `CLLocation.coordinate.latitude` | valeur absolue dans le tag, signe porté par le `Ref` |
| Longitude | `GPSLongitude` + `GPSLongitudeRef` | rationnel D/M/S + `E`/`W` | `CLLocation.coordinate.longitude` | idem |
| Date UTC | `GPSDateStamp` (`AAAA:MM:JJ`) | chaîne | `CLLocation.timestamp` | canal le plus fiable, car sans ambiguïté de fuseau |
| Heure UTC | `GPSTimeStamp` | 3 rationnels h/m/s | `CLLocation.timestamp` | |
| Date locale | `DateTimeOriginal` (`AAAA:MM:JJ HH:MM:SS`) | chaîne | horloge de l'appareil | écrit en complément, jamais seul |

> **Piège classique.** `DateTimeOriginal` est en heure locale *sans* fuseau.
> Écrire uniquement ce tag rend l'horodatage ambigu, et Panoramax privilégie
> alors `GPSDateStamp`/`GPSTimeStamp`. On écrit donc les deux, toujours.

## Recommandé

| Donnée | Tag | Source iOS | Notes |
|---|---|---|---|
| Cap de visée | `GPSImgDirection` + `GPSImgDirectionRef = "T"` | `CLHeading.trueHeading` ou `CLLocation.course` | `T` = nord géographique. Voir la règle de bascule ci-dessous |
| Altitude | `GPSAltitude` + `GPSAltitudeRef` | `CLLocation.altitude` | `Ref = 0` au-dessus du niveau de la mer, `1` en dessous |
| Vitesse | `GPSSpeed` + `GPSSpeedRef = "K"` | `CLLocation.speed` | m/s → km/h |
| Précision | `GPSHPositioningError` | `CLLocation.horizontalAccuracy` | remonté par Panoramax en `quality:horizontal_accuracy` |
| Marque | `Exif.Image.Make` | `"Apple"` | constante |
| Modèle | `Exif.Image.Model` | `utsname.machine` → nom commercial | ex. `iPhone 15 Pro` |
| Focale | `FocalLength`, `FocalLengthIn35mmFilm` | `AVCaptureDevice.activeFormat` | sert au calcul du champ de vision |
| Sous-seconde | `SubSecTimeOriginal` | horodatage de capture | utile pour ordonner une rafale |

### Règle de bascule du cap

La boussole magnétique est fiable à pied, mais faussée dans un véhicule
(carrosserie, support magnétique, haut-parleurs). Le cap issu du GPS est
inversement inutile à l'arrêt.

```
si location.speed > 2.0 m/s et location.course >= 0
    → cap = location.course           (route suivie, issue du GPS)
sinon si heading.headingAccuracy >= 0
    → cap = heading.trueHeading       (visée boussole, corrigée de la déclinaison)
sinon
    → pas de GPSImgDirection écrit    (mieux vaut absent que faux)
```

Un cap absent est traité correctement par Panoramax. Un cap faux dégrade la
séquence pour tous les réutilisateurs — la règle est donc de ne rien écrire
plutôt que d'écrire une valeur douteuse.

## Optionnel — XMP

`ImageIO` écrit l'EXIF sans difficulté, mais pas le XMP arbitraire. Ces tags
demandent d'injecter un segment `APP1` `http://ns.adobe.com/xap/1.0/` dans le
JPEG (`XMPInjector`).

| Donnée | Tag XMP | Source iOS |
|---|---|---|
| Lacet | `Xmp.Camera.Yaw` | `CMAttitude.yaw` |
| Tangage | `Xmp.Camera.Pitch` | `CMAttitude.pitch` |
| Roulis | `Xmp.Camera.Roll` | `CMAttitude.roll` |
| Projection 360° | `Xmp.GPano.ProjectionType = equirectangular` | hors périmètre v1 |

## Tags Mapillary

Panoramax accepte aussi `MAPLatitude`, `MAPLongitude`, `MAPGpsTime`,
`MAPCompassHeading`, `MAPDeviceMake`, `MAPDeviceModel`. Utile à connaître pour
lire des fichiers produits par d'autres applications, mais iPanoramax écrit de
l'EXIF standard : c'est ce que lisent aussi bien Panoramax que tous les autres
outils géospatiaux.

## Format de fichier

**JPEG uniquement.** Les iPhone capturent nativement en HEIC. Deux options :

1. demander explicitement du JPEG à `AVCapturePhotoOutput`
   (`AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])`) ;
2. capturer en HEIC puis transcoder.

**Retenu : l'option 1**, qui évite un ré-encodage et la perte de qualité qui va
avec. Le dictionnaire de métadonnées est passé à
`AVCapturePhotoSettings.metadata` *avant* la capture — zéro copie, zéro
recompression.
