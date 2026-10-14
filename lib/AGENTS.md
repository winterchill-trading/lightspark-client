# lib: lightspark-client library

Library `lightspark-client` (module `Lightspark_client`). Layers:

- Transport: `Config` (credentials, endpoints, `Sandbox` by default and `Live` only with
  `~live:true`), `Auth` (HTTP Basic, redaction), `Transport` (one HTTP exchange with its own TLS
  config; `Retry` retries 429 always and 408, 425, 5xx and timeouts only for idempotent calls,
  honouring `Retry-After`), `Api_error`.
- Lightning: `Graphql`, `Documents`, `Lightning_types`, `Lightning`.
- Grid: `Grid_types`, `Grid` (`all_pages`, sandbox funding, quotes).
- Verification: `P256` (ECDSA over SHA-256 on zarith) and `Webhook` (Lightspark HMAC-SHA256 and
  Grid `X-Grid-Signature`).

Rules:

- `Transport.record` writes status and body only, for fixtures; it must not write headers that carry
  credentials.
- A partial GraphQL result can carry both `data` and errors; keep both.
- Do not add an unbounded retry. Retry rules belong to `Retry` and are tested in `test/`.
