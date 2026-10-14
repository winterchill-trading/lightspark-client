# lightspark-client: agent guide

## Purpose

An Async OxCaml client and CLI for two payment APIs: the Lightspark GraphQL API (Lightning and UMA
nodes, wallets, invoices, payments) and the Grid REST API (customers, internal accounts, transfers,
exchange rates, quotes, sandbox tools). Both have webhook signature verification. Sandbox by
default; live mode needs an explicit opt-in.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | Library `lightspark-client` (module `Lightspark_client`): config, transport, errors, GraphQL and Grid clients, P-256, webhooks |
| `bin/` | The `lightspark` CLI |
| `docs/` | `api-notes.md`, notes on the two APIs as observed |
| `test/` | Fixture tests, retry and redaction tests; `test/live` and `test/tls` are separate test directories |
| `.github/` | CI workflow |

## Build, test, docs

Run from this repository, inside the workspace:

    opam exec --switch 5.2.0+ox -- dune build --root .. @lightspark-client/all
    opam exec --switch 5.2.0+ox -- dune build --root .. @lightspark-client/runtest

Several agents building at once need `DUNE_BUILD_DIR=_build-lightspark-client`.

Standalone, outside the workspace: add the organization's opam repository
(`opam repo add winterchill https://github.com/winterchill-trading/opam-repository.git`), install
the published dependencies, then run `dune build` here.

## Conventions

- Format this repository only: `dune build --root .. @lightspark-client/fmt --auto-promote`. Never
  `dune fmt` at the workspace root.
- Every module has an `.mli`; every public value has an odoc comment.
- Enumerations are strings, not variants, where the API adds values over time.
- Secrets never reach logs or errors. Use `Auth.redact` and `Auth.redact_headers` for anything that
  may print a request.
- Write guards are part of the contract: GraphQL writes that move funds read the node's network and
  refuse unless it is REGTEST; Grid writes that move money read `GET /config` and refuse unless the
  platform looks like a sandbox. Do not remove a guard to make a test pass.
- Fixtures are redacted recordings. Keep them free of ids and personal data.
- Comments for humans at non-obvious choices, such as the host-name check that `venue-net` lacks.

## Dependencies

- No sibling repositories. External: `core`, `core_unix`, `async`, `async_ssl`, `conduit-async`,
  `cohttp-async`, `uri`, `yojson`, `ppx_jane`, `ppx_yojson_conv`, `base64`, `cryptokit`, `zarith`.
- It does not use `venue-net`: it needs response headers and its own TLS configuration.
- No dependents in the organization yet. CI has no pins.

## CI

`.github/workflows/ci.yml` runs the `infra` ox-setup action with no pins, then `dune build` and
`dune test`. The `test/live` executable runs in CI with no credentials and prints one `skip` line.
The `obj-magic` job calls the reusable workflow in `winterchill-trading/infra`.
To check a run, use `gh run list --limit 1` and at most one `gh run watch <id> --exit-status`.

## Pitfalls

- macOS: `async_ssl` does not build against Homebrew OpenSSL 4, and zarith can pull in the wrong
  libssl. Without async_ssl the TLS setup silently has no TLS. See the macOS section of the README.
- For `wss`, `Conduit_async` builds an OpenSSL config without SNI; rebuild it with the host name.
  `cohttp-async` sets SNI itself for `https`.
- `Uri` has no `sexp_of_t` without `uri-sexp`.
- Async's `eprintf` and `eprint_s` are deprecated as errors; use `Print.eprintf`.
- The ppx_yojson_conv error text embeds the source path, which differs between workspace and opam
  builds. Keep it out of expect output.
- A `dune build` can hold `_build/.lock` for a long time; wrap agent builds in `timeout`.

## Where to read more

- `README.md` (environment, safety, library, CLI, endpoint coverage, known gaps)
- `docs/api-notes.md`
- `../specs/repos/lightspark-client.md` (design summary, known gaps, live status)
- `../oxcaml-claude-skills/AGENTS.md` and `../oxcaml-claude-skills/GOTCHAS.md`
- Skills in `../oxcaml-claude-skills/skills/`: `async-http-websocket`, `banking-standards`

## Never do

- Run the live write flow (`LIGHTSPARK_LIVE_WRITES=1`) or pass `-live` unless the task asks for it.
- Print, log or commit credentials, tokens, ids from a live account or personal data.
- Run `opam install`, `upgrade` or `pin` that would change `ocaml-variants`, `core`, `base`,
  `async` or `ppx_jane` on the shared `5.2.0+ox` switch.
- Publish, tag or release.
- Poll CI in a loop.
