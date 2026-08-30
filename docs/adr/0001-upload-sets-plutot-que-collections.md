# ADR 0001 — Utiliser les *upload sets* plutôt que l'API collections/items

- **Date** : 2026-08-30
- **Statut** : accepté

## Contexte

Panoramax expose deux API d'envoi qui coexistent.

1. **`POST /api/collections` puis `POST /api/collections/{id}/items`**, avec
   `picture` et `position`. Le client crée lui-même la séquence et ordonne les
   photos. C'est la spécification historique (`spec-api-upload`).
2. **Les *upload sets*** : le client crée un ensemble, y verse des fichiers, le
   clôt, et le serveur se charge du regroupement en séquences, du découpage
   temporel et spatial, et de la déduplication.

La première laisse plus de contrôle au client. La seconde délègue au serveur une
logique non triviale — et qui évolue.

## Décision

**Les *upload sets*.**

Trois raisons.

- **Le découpage est une décision serveur.** Les seuils (`split_distance`,
  `split_time`, `duplicate_distance`, `duplicate_rotation`) sont configurés par
  chaque instance et exposés par `GET /api/configuration`. Les réimplémenter
  côté client, c'est garantir une divergence à la première évolution.
- **La déduplication serveur est meilleure.** Elle voit ce qui est déjà publié
  autour, pas seulement la session en cours. Un client ne peut pas détecter
  qu'une photo à un feu rouge duplique une photo déjà présente sur l'instance.
- **Le suivi est plus riche.** `GET /api/upload_sets/{id}` donne un état agrégé
  (`items_status`), et `/files` donne le motif de refus par fichier. L'API
  collections oblige à interroger chaque item.

## Conséquences

- `PanoramaxKit` n'implémente **pas** l'API collections pour l'envoi. Elle
  reste pertinente en lecture (STAC), pas en écriture.
- Le client ne calcule pas ses séquences. L'écran de capture regroupe les
  clichés pour l'affichage, mais le découpage réel est celui que le serveur
  renvoie dans `associated_collections`. **L'interface doit refléter le
  découpage serveur, pas le sien** — sinon l'utilisateur voit une séquence dans
  l'app et deux sur la carte.
- Le `picture_id` est **généré à la capture** et persisté avec le cliché, pas
  généré au moment de l'envoi. C'est ce qui rend le POST idempotent et autorise
  une file d'envoi avec reprise agressive.
- `estimated_nb_files` est une estimation ; `POST /complete` est donc
  systématiquement appelé, puisque l'utilisateur peut supprimer des clichés
  avant envoi.

## Écarté

Implémenter les deux et laisser un réglage. Rejeté : deux chemins d'envoi, c'est
deux fois la surface de bugs sur la partie la plus critique de l'application,
pour un bénéfice utilisateur nul.
