# Changelog

Format : [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) · versionnage [SemVer](https://semver.org/lang/fr/).

## [Non publié]

### Ajouté
- Squelette du dépôt : licence MIT, CI GitHub Actions, XcodeGen, SwiftLint.
- `PanoramaxKit` : configuration d'instance, authentification « generate &
  claim », upload sets, corps multipart écrit sur disque pour les envois en
  tâche de fond.
- `Tools/panoramax-probe` : sonde en ligne de commande (`config`, `login`,
  `whoami`, `logout`, `diagnose`) contre une instance réelle.
- `Tools/check.sh` : build, tests et lint en une commande, journal dans
  `check.log`.
- `ImageMetadataKit` : modèle de capture, construction du dictionnaire EXIF/GPS
  pour ImageIO, écriture dans un JPEG sans recompression, et injection d'un
  segment APP1 XMP pour l'attitude de l'appareil (`Xmp.Camera.Yaw/Pitch/Roll`).

### Corrigé
- L'attente de revendication d'un jeton traite le **403** rendu par OSM-FR
  comme « pas encore rattaché à un compte », et non comme un refus définitif.

### Validé
- Authentification de bout en bout contre `panoramax.openstreetmap.fr`.
- **Phase 1 atteinte** : une photo dont toutes les métadonnées sont écrites par
  `ImageMetadataKit` est acceptée à l'ingestion par cette instance.

### Connu
- Le champ `user_agent` de `POST /api/upload_sets` fait rendre un 500 par
  l'instance OSM-FR alors qu'il figure dans sa spécification. Non envoyé pour
  l'instant ; à signaler au projet Panoramax.
- `items_status` et `ready` restent à zéro ou absents dans notre modèle alors
  que la photo est acceptée : le modèle a été bâti sur le résumé OpenAPI, pas
  sur une réponse réelle. À corriger sur la foi du JSON brut.
