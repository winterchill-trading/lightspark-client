# lightspark-client

An [OxCaml](https://oxcaml.org) / Async client for the two Lightspark APIs:

- the **GraphQL server API** (Lightning nodes, wallets, invoices, payments, test mode), and
- the **Grid API** (REST: customers, internal accounts, quotes, transfers, exchange rates,
  sandbox tools),

with webhook signature verification for both, and a small `lightspark` CLI.

## Quick start

```sh
cp .env.example .env          # fill in the two credentials
set -a; . ./.env; set +a
dune build
dune exec lightspark -- grid config
dune exec lightspark -- grid transactions -limit 5
dune exec lightspark -- grid rates -source USD -destination EUR
```

```ocaml
open Lightspark_client

let main () =
  let config = Config.of_env () |> Or_error.ok_exn in   (* Sandbox mode by default *)
  let grid = Grid.create config in
  match%map Grid.transactions ~limit:10 grid with
  | Ok page -> List.iter page.data ~f:(fun t -> print_endline t.id)
  | Error e -> print_s [%sexp (e : Api_error.t)]
```

## Environment

| Variable | Meaning |
|---|---|
| `LIGHTSPARK_CLIENT_ID` | API token client id (HTTP Basic user) |
| `LIGHTSPARK_CLIENT_SECRET` | API token secret (HTTP Basic password) |
| `LIGHTSPARK_GRAPHQL_URL` | optional, default `https://api.lightspark.com/graphql/server/2023-09-13` |
| `LIGHTSPARK_GRID_URL` | optional, default `https://api.lightspark.com/grid/2025-10-13` |
| `LIGHTSPARK_WEBHOOK_SECRET` | only for `lightspark webhook lightspark` |
| `LIGHTSPARK_RECORD_DIR` | optional: write every response (status and body only) here, for fixtures |
| `LIGHTSPARK_LIVE_WRITES` | `1` makes `test/live` run the sandbox write flow |

A token belongs to one API: a Grid token gets HTTP 401 `AuthenticationException` from the
GraphQL endpoint. Credentials are read only from the environment, never logged; errors and
retry logs pass through `Auth.redact`.

## Safety

`Config.t` has a mode, `Sandbox` (default) or `Live` (`~live:true`, CLI `-live`).

- GraphQL writes (`create_invoice`, test-mode invoice/payment, `fund_node`, `pay_invoice`)
  first read the node's `bitcoin_network` and refuse unless it is `REGTEST`.
- Grid writes that can move money (create customer, create/execute quote) first read
  `GET /config` and refuse unless the platform looks like a sandbox (its UMA domain and
  proxy subdomain contain `sandbox`; the API has no explicit flag). `/sandbox/*`
  endpoints are rejected by production keys on the server side.

## Library

| Module | What |
|---|---|
| `Config` | credentials, endpoints, mode, from env; redacted sexp |
| `Auth` | Basic header, `redact`, `redact_headers` |
| `Transport` | one HTTP exchange (cohttp-async, TLS with host-name check), `Retry` (429 always, 408/425/5xx/timeouts only when idempotent, honours `Retry-After`), `record` |
| `Api_error` | `Http` (status, Grid `code`/`reason`, request id), `Graphql` (errors with `error_name`), `Rate_limited`, `Transport`, `Decode`, `Refused` |
| `Graphql` | POST a document + variables, return `data` or a typed error |
| `Documents` | GraphQL documents with the official SDK fragments and aliases |
| `Lightning_types`, `Lightning` | account, nodes and balances, wallets, transactions (connections), invoices, decoded payment requests; test-mode writes |
| `Grid_types`, `Grid` | config, customers, internal accounts, transactions, exchange rates, quotes; `all_pages`; sandbox funding, customer creation, quote create/execute |
| `P256` | ECDSA P-256/SHA-256 verification over zarith (PEM SPKI keys, DER or raw signatures) |
| `Webhook` | `Lightspark.verify` (HMAC-SHA256 hex, `lightspark-signature`) and `Grid.verify` (`X-Grid-Signature`, P-256) |

`cohttp-async` is used directly rather than through `venue-net` because the client needs
response headers (`x-request-id`, `Retry-After`) and its own TLS configuration.

## CLI

```
lightspark account | nodes | wallets | transactions [-limit N] [-after CURSOR]
lightspark invoice create -node-id ID -amount-msats N [-memo T] [-live]
lightspark invoice lookup -payment-hash HEX
lightspark invoice test-create -node-id ID -amount-msats N
lightspark invoice test-pay -node-id ID -invoice BOLT11
lightspark fund-node -node-id ID [-amount-sats N]
lightspark grid config | customers | accounts | platform-accounts | transactions | rates
lightspark grid transaction -id ID | quote -id ID
lightspark grid sandbox-fund -account-id ID -amount N
lightspark grid send-uma -account-id ID -to UMA -currency CCY -amount N [-live]
lightspark webhook grid -body FILE -signature SIG -public-key PEM
lightspark webhook lightspark -body FILE -signature HEX
```

Output is JSON (`-sexp` for sexps). Errors go to stderr and exit 1.

## Endpoint coverage

| Endpoint | Library | Verified |
|---|---|---|
| Grid `GET /config` | `Grid.platform_config` | live |
| Grid `GET /customers` (+cursor) | `Grid.customers` | live |
| Grid `GET /customers/{id}` | `Grid.customer` | fixtures |
| Grid `POST /customers` | `Grid.create_individual_customer` | live (sandbox) |
| Grid `GET /customers/internal-accounts` | `Grid.customer_internal_accounts` | live |
| Grid `GET /platform/internal-accounts` | `Grid.platform_internal_accounts` | live |
| Grid `GET /internal-accounts/{id}` | `Grid.internal_account` | not exercised |
| Grid `GET /transactions` (+cursor, 3 pages) | `Grid.transactions`, `Grid.all_pages` | live |
| Grid `GET /transactions/{id}` | `Grid.transaction` | live |
| Grid `GET /exchange-rates` | `Grid.exchange_rates` | live |
| Grid `POST /sandbox/internal-accounts/{id}/fund` | `Grid.sandbox_fund_internal_account` | live (sandbox) |
| Grid `POST /quotes` | `Grid.create_quote` | live (sandbox, USD to own USDC account) |
| Grid `POST /quotes/{id}/execute` | `Grid.execute_quote` | live (sandbox) |
| Grid `GET /quotes/{id}` | `Grid.quote` | live (404 path) |
| Grid webhooks (`X-Grid-Signature`) | `Webhook.Grid.verify` | OpenSSL-signed vector |
| GraphQL `current_account` | `Lightning.current_account` | live 401 only; fixtures |
| GraphQL `nodes`, `wallets`, `transactions` | `Lightning.*` | fixtures (SDK shape) |
| GraphQL `invoice_for_payment_hash`, `decoded_payment_request` | `Lightning.*` | fixtures |
| GraphQL `create_invoice`, `create_test_mode_invoice`, `create_test_mode_payment`, `fund_node`, `pay_invoice` | `Lightning.*` | fixtures and the REGTEST guard |
| GraphQL webhooks (`lightspark-signature`) | `Webhook.Lightspark.verify` | HMAC checked against Python's `hmac` |

## Tests

- `dune test` runs the fixture tests (redacted Grid responses recorded from the sandbox;
  GraphQL bodies in the official SDK's response shape plus the live 401 body), the
  retry/redaction/P-256 unit tests, `test/tls` (expired, self-signed and wrong-host
  certificates must be rejected; skipped when offline) and `test/live`.
- `test/live/live_check.exe` prints one `skip` line without credentials (always the case
  in CI). With credentials it runs the Grid reads and the GraphQL account read; with
  `LIGHTSPARK_LIVE_WRITES=1` it also creates a sandbox customer, funds its USD account
  with $10 through `/sandbox/...`, quotes and executes $5 USD into the customer's own USDC
  account and reads back the transaction. It prints counts and statuses, never ids or
  personal data.

Verified live on 2026-10-13 with a Grid sandbox token: every row marked "live" above.

## Known gaps

- **GraphQL API not verified live**: the provided token is a Grid token and the GraphQL
  endpoint answers 401 `Not logged in.`. Documents, decoders and guards are tested on
  fixtures shaped like the official SDK responses; the first run with a GraphQL token may
  need alias/field fixes (in particular `balances` on the `LightsparkNode` interface).
- **Signed GraphQL mutations**: `pay_invoice` works only for remote-signing nodes; OSK
  nodes need `X-Lightspark-Signing` (secp256k1 over the payload with nonce and expiry),
  not implemented.
- **UMA sends in this sandbox**: `$success.usd@sandbox.uma.money` from the docs fails with
  `INVALID_UMA_ADDRESS`; paying a UMA address on our own platform fails with
  `SENDER_NOT_ACCEPTED` because the platform webhook must approve incoming payments; and
  transfers between two customers are disabled for this platform. The live write flow
  therefore converts USD into the same customer's USDC account.
- Grid customers need a deliverable email when the platform has embedded wallets; the
  live check uses plus-addresses on the org mailbox.
- The `currency` filter on `/customers/internal-accounts` returned nothing for a
  just-created customer; the live check lists all accounts and filters locally.
- Not covered: external accounts, KYC/documents, cards, SCA, agents, embedded-wallet auth,
  UMA invitations, Grid API token management, webhook endpoint configuration (account
  settings are deliberately not touched).

## macOS and OpenSSL

`https` needs `async_ssl` built against OpenSSL 3; see the notes in
[hl-client](https://github.com/winterchill-trading/hl-client#macos-and-openssl).
