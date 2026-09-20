# panoramax-probe

Outil en ligne de commande pour éprouver `PanoramaxKit` et `ImageMetadataKit`
contre une vraie instance Panoramax, sans passer par Xcode ni le simulateur.

```bash
cd Tools/panoramax-probe

# Configuration publique d'une instance (aucun compte nécessaire)
swift run panoramax-probe config panoramax.openstreetmap.fr

# Flux complet : generate → claim dans le navigateur → /users/me
swift run panoramax-probe login panoramax.openstreetmap.fr

# Vérifier le jeton mémorisé
swift run panoramax-probe whoami

# Réponses brutes, quand un code de statut ne suffit pas à comprendre un refus
swift run panoramax-probe diagnose

# Révoquer le jeton côté serveur et l'oublier localement
swift run panoramax-probe logout
```

## L'épreuve du feu

`upload` écrit nos métadonnées dans un JPEG, relit le fichier produit, puis —
sur demande — l'envoie et rapporte le verdict du serveur. C'est le seul test qui
prouve que la chaîne complète fonctionne : aucune fixture ne peut dire si
Panoramax accepte un fichier.

```bash
# Essai à blanc : écrit photo.panoramax.jpg et affiche ce qu'il contient
swift run panoramax-probe upload ~/photos/photo.jpg

# Envoi réel, puis suppression de la séquence
swift run panoramax-probe upload ~/photos/photo.jpg --send \
    --lat 45.9237 --lon 6.8694 --heading 137
```

| Option | Effet |
|---|---|
| `--send` | envoie réellement ; sans lui, tout reste local |
| `--keep` | conserve la séquence au lieu de la supprimer |
| `--public` | accepte une séquence publique quand l'instance ne propose pas `owner-only` |
| `--lat` `--lon` `--alt` | position à inscrire (défaut : Tour Eiffel) |
| `--heading` | cap de visée en degrés |
| `--title` | titre de l'upload set |
| `--token` | utiliser ce jeton plutôt que celui mémorisé |

> **Un envoi crée de la donnée réelle sur un commun partagé.** L'outil lit
> d'abord `/api/configuration` : si l'instance déclare `owner-only`, l'essai
> part en visibilité masquée. Sinon il **s'arrête** plutôt que de créer une
> séquence publique à ton insu — `--public` force le passage. Dans tous les cas
> la séquence est supprimée à la fin, sauf `--keep` ; si la suppression échoue,
> l'outil donne l'identifiant à retirer à la main.

Quand la création d'un upload set échoue, l'outil réessaie en retirant les
champs un à un et indique lequel débloque la situation : une erreur 500 rend
une page générique qui ne nomme pas le champ fautif.

Le traitement serveur — floutage compris — peut durer plusieurs minutes sur une
instance chargée. Inutile de renvoyer la photo pour savoir où il en est :

```bash
swift run panoramax-probe status e6f2fce2-47f5-40b5-aa96-c16ccdefe9b1
swift run panoramax-probe status e6f2fce2-47f5-40b5-aa96-c16ccdefe9b1 --delete
```

## Stockage du jeton

> Le jeton est enregistré **en clair** dans `~/.config/ipanoramax/tokens.json`.
> Acceptable pour un outil de mise au point sur ta propre machine ; dans
> l'application, il va au Keychain. Ne versionne jamais ce fichier, et révoque
> le jeton avec `logout` quand tu as fini.
