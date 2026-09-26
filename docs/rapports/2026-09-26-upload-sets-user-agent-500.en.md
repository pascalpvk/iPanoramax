# POST /api/upload_sets returns HTTP 500 when the `user_agent` field is present

*For <https://gitlab.com/panoramax/server/api/-/issues>*

## Summary

On `panoramax.openstreetmap.fr`, `POST /api/upload_sets` answers **500 Internal
Server Error** as soon as the JSON body contains a `user_agent` key —
**whatever its value**, including the empty string and `null`. The same request
without that key is accepted.

The field is part of the route's OpenAPI specification
(`GeoVisioPostUploadSet`), documented as "Client software identifier". A
third-party client that follows the specification is therefore blocked at the
very first step of an upload.

## Environment

| | |
|---|---|
| Instance | `panoramax.openstreetmap.fr` |
| API version | `2.15.1-22-gf754cc9` (from `GET /api/configuration`) |
| Route | `POST /api/upload_sets` |
| Authentication | JWT bearer token, account role `user`, `tos_accepted: true` |
| Tools | `curl` and a home-grown Swift client — identical results |
| Tested on | 26 September 2026 |

The same account uploads without trouble through the web interface, and
`POST /api/collections` (the older upload route) responds normally.

## Minimal reproduction

Verified with `curl`, independently of any client: `200` for the control,
`500` with the `user_agent` key.

```bash
TOKEN="<your token>"
BASE="https://panoramax.openstreetmap.fr/api"

# Control — accepted
curl -i -X POST "$BASE/upload_sets" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"repro"}'
# → HTTP/2 200, Location header present

# Same request with user_agent set to null — rejected
curl -i -X POST "$BASE/upload_sets" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"repro","user_agent":null}'
# → HTTP/2 500, generic Flask error page
```

Remember to remove the upload set created by the control:
`DELETE $BASE/upload_sets/<id>`.

## Full matrix

Three attempts per case, all identical. No intermittency, so this is not a
load-related failure.

| JSON body | Status codes |
|---|---|
| `{"title":"iPanoramax repro"}` | `200 200 200` |
| `{"title":"…","estimated_nb_files":1,"sort_method":"time-asc","visibility":"owner-only"}` | `200 200 200` |
| `{"title":"…","user_agent":"panoramax-probe (iPanoramax)"}` | `500 500 500` |
| `{"title":"…","user_agent":"iPanoramax"}` | `500 500 500` |
| `{"title":"…","user_agent":"iPanoramax 1.0"}` | `500 500 500` |
| `{"title":"…","user_agent":"iPanoramax (test)"}` | `500 500 500` |
| `{"title":"…","user_agent":""}` | `500 500 500` |
| `{"title":"…","user_agent":null}` | `500 500 500` |

The second control shows that the other optional fields —
`estimated_nb_files`, `sort_method`, `visibility` — cause no trouble.

## What the matrix establishes

It is the **presence of the key** that triggers the error, not its contents. An
empty value fails just as a long one does; `null` fails just as a string does.
That rules out escaping, length and special characters.

Worth noting: this route rejects other invalid input cleanly. With no
authorization header it answers `401` together with
`{"message":"Authentication is mandatory"}`. A 500 is therefore not how this
API normally signals input it refuses — it looks like an uncaught exception.

A hypothesis, without having read the deployed code: the field seems to take a
path that runs as soon as the key is present in the deserialised payload — a
write to a column missing from the deployed schema, or a helper called on a
value that may be null. The instance logs should hold the actual traceback; the
500 response carries no request identifier that would let a contributor point
you at it.

## Impact

A client that fills in `user_agent` as the specification intends — which is
precisely what the field is for — cannot create a single upload set. The
generic Flask error names no field, so diagnosing it requires bisecting the
request body field by field.

Current client-side workaround: do not send `user_agent`.

## Suggestions

1. Accept `null` and the empty string, or reject the field with an explicit
   **400** rather than a 500.
2. If the field is no longer supported, remove it from the route's OpenAPI
   specification.
3. Expose a request identifier in 5xx responses, so contributors can tie an
   error to a server-side trace.

## Context

Found while building **iPanoramax**, a native iOS client for Panoramax
(<https://github.com/pascalpvk/iPanoramax>, MIT licensed). The diagnostic tool
that produced this matrix is part of that repository:
`Tools/panoramax-probe`, `reproduce` command.

Happy to test a fix against this instance, or to provide any further detail.
