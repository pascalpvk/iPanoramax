# ADR 0002 — La base ne porte que des chemins ; les photos vivent sur le disque

- **Date** : 2026-09-26
- **Statut** : accepté

## Contexte

Une séquence de 500 clichés pèse plusieurs gigaoctets. Il faut décider où ces
octets résident, et comment ils restent d'accord avec les lignes qui les
décrivent.

SwiftData sait stocker des `Data`, et l'attribut `.externalStorage` déporte
automatiquement les gros blobs hors du fichier SQLite. C'est tentant : un seul
magasin, une seule transaction, rien à réconcilier.

Deux contraintes s'y opposent.

1. **L'envoi en tâche de fond n'accepte que des fichiers.** Une `URLSession` en
   configuration `.background` ne propose que `uploadTask(with:fromFile:)`. Une
   photo rangée dans la base devrait en ressortir, être réécrite dans un
   fichier temporaire, puis envoyée — pour chaque cliché, et de nouveau à
   chaque reprise.
2. **Le fichier est déjà l'unité de travail.** `ImageMetadataKit` écrit un JPEG
   complet, EXIF et XMP compris. Le stocker ailleurs que comme fichier, c'est
   ajouter une conversion à l'aller et une au retour, sans rien y gagner.

S'ajoute une raison de robustesse : une base de plusieurs gigaoctets est lente
à migrer, pénible à sauvegarder, et illisible quand quelque chose se passe mal.

## Décision

**Les JPEG sont des fichiers ; la base ne porte que de quoi les retrouver.**

- Emplacement : `Application Support/captures/<session>/<cliché>.jpg`.
  `Application Support` et non `Caches` : le système vide `Caches` sous
  pression de stockage, et perdre une séquence pas encore envoyée n'est pas une
  option.
- Le nom du fichier est l'UUID du cliché — qui est aussi son `picture_id`
  Panoramax (cf. ADR 0001). **Un seul identifiant de l'obturateur à
  l'ingestion.**
- Le chemin n'est pas stocké : il se calcule. Une base qui porterait des chemins
  absolus deviendrait fausse au premier changement de conteneur applicatif,
  après une restauration de sauvegarde par exemple.
- `PhotoFileStore` tient le disque, `CaptureStore` tient la base,
  `CaptureLibrary` tient les deux d'accord.

## L'ordre des écritures, et pourquoi il est asymétrique

- À l'écriture : **le fichier d'abord, la ligne ensuite.**
- À la suppression : **la ligne d'abord, le fichier ensuite.**

Les deux règles vont dans le même sens et donnent le même invariant :

> **Toute ligne a son fichier. Certains fichiers peuvent n'avoir aucune ligne.**

Le déséquilibre est volontaire. Une interruption au mauvais moment laisse donc
toujours un *fichier orphelin*, jamais une *ligne orpheline* — et ce n'est pas
symétrique du tout :

- un fichier orphelin ne coûte que des octets, invisibles, que
  `sweepOrphanFiles(in:)` récupère ;
- une ligne orpheline désigne une photo qui n'existe pas : vignette cassée à
  l'écran, et un envoi que la file retentera indéfiniment sans jamais pouvoir
  aboutir.

Quand l'inscription en base échoue immédiatement, le fichier est retiré dans la
foulée : l'appelant retrouve l'état d'avant, pas un demi-cliché.

## Conséquences

- Le schéma est **versionné dès la première version**, sans étape de migration.
  C'est précisément le moment où cela ne coûte rien ; quand `UploadTask`
  arrivera en phase 3, l'ajout sera une migration et non un effacement de la
  base des premiers utilisateurs.
- Les états persistés (`SessionState`, `ShotState`) sont stockés **en chaînes**,
  pas en énumérations : `#Predicate` compare des chaînes sans difficulté, et une
  valeur écrite par une version ultérieure de l'app se relit encore au lieu de
  faire échouer le décodage de la ligne entière.
- Le mode de déclenchement est rangé en **deux colonnes plates**
  (`modeKind`, `modeValue`) plutôt qu'en `CaptureMode` sérialisé : ajouter un
  mode dans `GeoKit` ne doit pas changer la forme du schéma — donc pas de
  migration pour une raison qui n'en est pas une.
- `Shot` porte `sessionID` **en plus** de la relation. `#Predicate` traverse mal
  les relations ; une colonne plate rend les requêtes triviales, pour seize
  octets par ligne.
- Rien de ce qui entre dans `CaptureStore` ni de ce qui en sort n'est un objet
  SwiftData : un `ModelContext` n'est pas `Sendable`, il reste enfermé dans
  l'acteur, et les frontières ne voient que des valeurs (`ShotDraft`,
  `SessionSnapshot`, `ShotSnapshot`).
- L'avancement du **traitement serveur** (découpage, floutage) n'est pas
  persisté. Il change sans nous, parfois plusieurs minutes après l'envoi : on
  le lit en direct sur l'API plutôt que d'en garder une copie périmée.

## Écarté

- **`@Attribute(.externalStorage)` sur un `Data`.** Résout le poids du fichier
  SQLite, pas le besoin d'un chemin pour l'envoi en tâche de fond.
- **`@Attribute(.unique)` sur les identifiants.** La contrainte transforme une
  insertion en fusion silencieuse. L'idempotence est plus lisible écrite dans
  le magasin — on cherche, et on rend ce qui existe — que déduite d'un
  comportement d'*upsert*.
- **Un compteur de clichés dénormalisé sur la session.** `fetchCount` répond par
  une requête d'agrégat, sans charger la relation ni risquer de dériver.
