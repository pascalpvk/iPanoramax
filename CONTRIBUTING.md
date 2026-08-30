# Contribuer à iPanoramax

Merci de l'intérêt porté au projet. Voici comment travailler dessus sans
friction.

## Mise en place

```bash
brew install xcodegen swiftlint swiftformat
xcodegen generate --spec App/project.yml
```

Le `.xcodeproj` est **généré**, jamais versionné : toute modification de la
structure du projet passe par `App/project.yml`.

## Avant de proposer une modification

```bash
cd Packages/PanoramaxKit && swift test
swiftlint lint --strict
```

## Conventions

- **Commits** : [Conventional Commits](https://www.conventionalcommits.org/fr/),
  comme les dépôts Panoramax. `feat:`, `fix:`, `docs:`, `refactor:`, `test:`,
  `chore:`.
- **Branches** : `feat/nom-court`, `fix/nom-court`. La branche par défaut est
  `main`.
- **Swift 6, concurrence stricte.** Un avertissement de concurrence est traité
  comme une erreur : ils sont pénibles à rattraper après coup.
- **En-tête de fichier** : chaque fichier source commence par
  `// SPDX-License-Identifier: MIT`.
- **Langue** : le code et les identifiants sont en anglais, les commentaires et
  la documentation en français.

## Ce qui n'est pas négociable

Trois règles tiennent la qualité des données produites, et donc l'intérêt du
projet pour la communauté Panoramax.

1. **Aucune photo n'est envoyée sans position ni horodatage valides.** Une photo
   incomplète est rejetée à l'ingestion — autant ne pas l'envoyer.
2. **Un cap douteux n'est pas écrit.** Mieux vaut un `GPSImgDirection` absent
   qu'une valeur fausse : un cap erroné dégrade la séquence pour tous les
   réutilisateurs.
3. **Aucun SDK d'analytique ni de suivi tiers.** L'app ne transmet rien d'autre
   que ce que l'utilisateur publie délibérément.

## Ajouter une dépendance

Elles se justifient au cas par cas. À ce jour, une seule est prévue :
MapLibre Native, pour la carte. Toute proposition d'ajout doit préciser ce
qu'elle apporte que les frameworks Apple ne font pas, et sous quelle licence
elle est distribuée.

## Décisions d'architecture

Les choix structurants sont consignés dans `docs/adr/`, au format ADR (une page,
datée : contexte, décision, conséquences). Une modification qui remet en cause
une décision existante ouvre un nouvel ADR plutôt que de réécrire l'ancien.
