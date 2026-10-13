# Lightspark API notes

What we learned while building this client (October 2026). Two separate APIs share the
`api.lightspark.com` host and HTTP Basic credentials, but a token belongs to one of them.

## Two APIs, two kinds of token

| | GraphQL server API (Lightning nodes, wallets, UMA) | Grid API (global accounts, fiat and stablecoin rails) |
|---|---|---|
| Base URL | `https://api.lightspark.com/graphql/server/2023-09-13` | `https://api.lightspark.com/grid/2025-10-13` |
| Style | GraphQL over `POST` | REST, JSON, camelCase |
| Version | date in the path (`2023-09-13` is still the SDK default) | date in the path (`2025-10-13`, the OpenAPI `info.version`) |
| Auth | Basic `<api token client id>:<client secret>` | same scheme, Grid token |
| Sandbox | REGTEST nodes ("test mode") | sandbox platform with sandbox keys, same base URL |

A Grid sandbox token is rejected by the GraphQL endpoint with HTTP 401 and a GraphQL body
(`{"data":{"current_account":null},"errors":[{"message":"Not logged in.",
"extensions":{"error_name":"AuthenticationException"}}]}`); the error is in the body even
though the status is not 200, so decode the body before looking at the status.

## GraphQL server API

- Request: `POST` JSON `{"operationName", "query", "variables"}`. The SDKs also send
  `X-GraphQL-Operation: <operation name>` and a `User-Agent`/`X-Lightspark-SDK` header.
- Bodies over 1 KB may be compressed (`Content-Encoding: zstd` or `deflate`); optional.
- Responses: `{"data": ..., "errors": [{"message", "path", "extensions": {"error_name"}}]}`.
  A partial result can carry both.
- Field names are snake_case. The SDK queries alias every field with a type prefix
  (`account_id: id`, `currency_amount_original_value: original_value`) so that fragments
  for different types can be merged into one flat object; the aliases are part of the
  response shape, so parsers must follow the document.
- `CurrencyAmount`: `original_value` (int, in `original_unit`), `original_unit`
  (`SATOSHI`, `MILLISATOSHI`, `USD`, ...), plus a preferred-currency conversion.
- Connections: `count`, `page_info { has_next_page end_cursor }`, `entities`; page with
  `first` and `after`.
- Signed mutations (`pay_invoice`, `request_withdrawal`, ...) on nodes with an OSK need
  `X-Lightspark-Signing` (secp256k1 signature of the payload, which then also carries a
  `nonce` and `expires_at`). Remote-signing nodes do not. Reads never need it.
- Test mode: REGTEST nodes can be funded with `fund_node` (default 10,000,000 sat),
  `create_test_mode_invoice` makes an invoice that a test node can pay, and
  `create_test_mode_payment` simulates an incoming payment to one of our invoices.
- Webhooks: header `lightspark-signature`, lowercase hex HMAC-SHA256 of the raw body keyed
  with the webhook secret. Body `{event_type, event_id, timestamp, entity_id, wallet_id?}`.

## Grid API

- REST under the versioned base URL. Errors are `{"code", "reason", "details"?}` with
  ordinary HTTP statuses (400, 401, 403, 404, 405 `METHOD_NOT_ALLOWED`, 409, 412, 422, 424,
  429 `RATE_LIMITED`, 5xx). 408, 429, 502 and 504 are documented as retryable.
- Every response carries `x-request-id` (and `x-trace-id`); log it.
- Rate limits: no `X-RateLimit-*` headers on normal responses; a 429 may carry
  `Retry-After` (seconds).
- Pagination: `limit` (1..100, default 20) and `cursor`; responses are
  `{"data": [...], "hasMore", "nextCursor"?, "totalCount"?}`. `nextCursor` is absent on the
  last page.
- Idempotency: `Idempotency-Key` header on creates (customers, internal accounts,
  transfers, quotes). A replay returns 200 with the original object; a different body
  under the same key is 409.
- Amounts are integers in the currency's smallest unit; the `currency` object carries
  `code`, `decimals`, `name`, `symbol`.
- Ids are typed strings: `Customer:<uuid>`, `InternalAccount:<uuid>`, `Transaction:<uuid>`,
  `Quote:<uuid>`, `Platform:<uuid>`.
- `GET /internal-accounts` does not exist (405); use `/customers/internal-accounts` or
  `/platform/internal-accounts`.
- Sandbox: same base URL, sandbox keys from the dashboard. `/sandbox/*` endpoints
  (fund an internal account, simulate an inbound send, card simulations) work only with
  sandbox keys. Magic values pick outcomes: UMA addresses like
  `$success.usd@sandbox.uma.money`, external account number suffixes (`002` fails,
  `003` slow, `005` returned, `010`..`013` specific failure reasons).
- There is no explicit "this is sandbox" flag in the API. A sandbox platform's
  `umaDomain` and `proxyUmaSubdomain` in `GET /config` contain `sandbox`; the client uses
  that as its sandbox check before any money-moving write.
- Webhooks: header `X-Grid-Signature`, either raw base64 or JSON `{"v":"1","s":"<base64>"}`;
  ECDSA P-256 over SHA-256 of the raw body, DER-encoded signature, verified with the
  platform's PEM public key from the dashboard. Body `{id, type: "OBJECT.EVENT", timestamp,
  data}`; `id` is the idempotency key for deliveries.

## TLS (checked 2026-10-13)

The switch has conduit-async 8.0.0, cohttp-async 6.2.1 and async_ssl v0.18 preview.
`Async_ssl.Ssl.client` defaults to `Verify_peer` and loads the system default verify
paths when no `ca_file`/`ca_path` is given, so an expired or self-signed chain fails the
handshake (`certificate verify failed`). But nothing checks that the certificate names the
host: cohttp-async passes `~hostname` only for SNI, and conduit-async's `verify` callback
defaults to `fun _ -> true`. Measured: with the default config a request to
`https://wrong.host.badssl.com/` succeeds with status 200.

`Transport.cohttp` therefore passes its own `Conduit_async.V2.Ssl.Config` with
`Verify_peer` and a `verify` callback that requires a peer certificate and
`Ssl.Connection.check_peer_certificate_host` for the URI host. `test/tls/tls_check.exe`
(part of `dune test`) asserts that expired, self-signed and wrong-host certificates are
rejected and that `api.lightspark.com` still connects; it prints `skip` and passes when the
hosts are unreachable.
