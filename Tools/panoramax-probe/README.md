# panoramax-probe

Outil en ligne de commande pour éprouver `PanoramaxKit` contre une vraie
instance Panoramax, sans passer par Xcode ni le simulateur.

Il sert à dérisquer l'authentification — la brique dont dépend tout le reste —
et à vérifier que le client décode bien ce que renvoient les instances réelles.

```bash
cd Tools/panoramax-probe

# Lire la configuration publique d'une instance (aucun compte nécessaire)
swift run panoramax-probe config panoramax.openstreetmap.fr

# Flux complet : generate → claim dans le navigateur → /users/me
swift run panoramax-probe login panoramax.openstreetmap.fr

# Vérifier le jeton mémorisé
swift run panoramax-probe whoami panoramax.openstreetmap.fr

# Révoquer le jeton côté serveur et l'oublier localement
swift run panoramax-probe logout panoramax.openstreetmap.fr
```

L'instance par défaut est `panoramax.openstreetmap.fr`.

> **Le jeton est stocké en clair** dans `~/.config/ipanoramax/tokens.json`.
> C'est acceptable pour un outil de mise au point sur ta propre machine ; dans
> l'application, le jeton va au Keychain. Ne versionne jamais ce fichier et
> révoque le jeton avec `logout` quand tu as fini.
