# POST /api/upload_sets : la présence du champ `user_agent` provoque un HTTP 500

*Rapport destiné à <https://gitlab.com/panoramax/server/api/-/issues>*

## Résumé

Sur `panoramax.openstreetmap.fr`, `POST /api/upload_sets` répond **500 Internal
Server Error** dès que le corps JSON contient la clé `user_agent`, **quelle que
soit sa valeur** — y compris la chaîne vide et `null`. La même requête sans
cette clé est acceptée.

Le champ figure pourtant dans la spécification OpenAPI de la route
(`GeoVisioPostUploadSet`), documenté comme « Client software identifier ». Un
client tiers qui suit la spécification est donc bloqué à la première étape d'un
envoi.

## Environnement

| | |
|---|---|
| Instance | `panoramax.openstreetmap.fr` |
| Version d'API | `2.15.1-22-gf754cc9` (via `GET /api/configuration`) |
| Route | `POST /api/upload_sets` |
| Authentification | jeton JWT porteur, compte au rôle `user`, `tos_accepted: true` |
| Outils | `curl` et un client Swift maison — mêmes résultats |
| Date des essais | 26 septembre 2026 |

Le même compte publie sans difficulté via l'interface web, et `POST
/api/collections` (ancienne route d'envoi) répond normalement.

## Reproduction minimale

Vérifiée en `curl`, indépendamment de tout client : `200` pour le témoin, `500`
avec la clé `user_agent`.

```bash
TOKEN="<votre jeton>"
BASE="https://panoramax.openstreetmap.fr/api"

# Témoin — accepté
curl -i -X POST "$BASE/upload_sets" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"repro"}'
# → HTTP/2 200, en-tête Location présent

# Même requête, clé user_agent à null — refusé
curl -i -X POST "$BASE/upload_sets" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"repro","user_agent":null}'
# → HTTP/2 500, page d'erreur Flask générique
```

Penser à supprimer l'ensemble créé par le témoin :
`DELETE $BASE/upload_sets/<id>`.

## Matrice complète

Trois essais par cas, tous identiques. Aucune intermittence : ce n'est pas un
problème de charge.

| Corps JSON | Statuts |
|---|---|
| `{"title":"iPanoramax repro"}` | `200 200 200` |
| `{"title":"…","estimated_nb_files":1,"sort_method":"time-asc","visibility":"owner-only"}` | `200 200 200` |
| `{"title":"…","user_agent":"panoramax-probe (iPanoramax)"}` | `500 500 500` |
| `{"title":"…","user_agent":"iPanoramax"}` | `500 500 500` |
| `{"title":"…","user_agent":"iPanoramax 1.0"}` | `500 500 500` |
| `{"title":"…","user_agent":"iPanoramax (test)"}` | `500 500 500` |
| `{"title":"…","user_agent":""}` | `500 500 500` |
| `{"title":"…","user_agent":null}` | `500 500 500` |

Le second témoin montre que les autres champs optionnels — `estimated_nb_files`,
`sort_method`, `visibility` — ne posent aucun problème.

## Ce que la matrice établit

C'est la **présence de la clé** qui déclenche l'erreur, pas son contenu. Une
valeur vide échoue comme une valeur longue ; `null` échoue comme une chaîne.
Cela écarte un problème d'échappement, de longueur ou de caractères spéciaux.

À noter que cette route répond proprement aux autres entrées invalides : sans
en-tête d'autorisation, elle rend un `401` accompagné de
`{"message":"Authentication is mandatory"}`. Le 500 n'est donc pas la manière
habituelle dont l'API signale une entrée qu'elle refuse — c'est une exception
non rattrapée.

Hypothèse, sans avoir lu le code déployé : le champ semble emprunter un chemin
exécuté dès que la clé est présente dans la charge utile désérialisée — écriture
vers une colonne absente du schéma déployé, ou appel d'un utilitaire de
traitement non protégé contre une valeur nulle. Les journaux de l'instance
devraient contenir la trace exacte ; les en-têtes de la réponse 500 ne portent
pas d'identifiant de requête permettant de la retrouver depuis l'extérieur.

## Impact

Un client qui remplit `user_agent` en suivant la spécification — ce qui est
précisément l'usage documenté du champ — échoue à créer le moindre envoi. Le
message d'erreur générique de Flask ne nomme pas le champ fautif, si bien que le
diagnostic demande une bisection champ par champ du corps de requête.

Contournement actuel côté client : ne pas envoyer `user_agent`.

## Suggestions

1. Rendre le champ tolérant à `null` et à la chaîne vide, ou le rejeter avec un
   **400** explicite plutôt qu'un 500.
2. Si le champ n'est plus pris en charge, le retirer de la spécification
   OpenAPI de la route.
3. Exposer un identifiant de requête dans les réponses 5xx, pour que les
   contributeurs puissent rattacher une erreur à une trace serveur.

## Contexte

Relevé pendant le développement d'**iPanoramax**, un client iOS natif pour
Panoramax (<https://github.com/pascalpvk/iPanoramax>, licence MIT). L'outil de
diagnostic qui a produit cette matrice fait partie du dépôt :
`Tools/panoramax-probe`, commande `reproduce`.
