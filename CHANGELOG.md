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
  pour ImageIO, écriture dans un JPEG sans recompression.

### Corrigé
- L'attente de revendication d'un jeton traite le **403** rendu par OSM-FR
  comme « pas encore rattaché à un compte », et non comme un refus définitif.

### Validé
- Authentification de bout en bout contre `panoramax.openstreetmap.fr`.
