# .github: lightspark-client CI

`workflows/ci.yml` builds and tests this repository with the `infra` ox-setup action and no pins.

Rules:

- CI has no API credentials and must stay that way. The live check prints `skip`.
- Keep the obj-magic job calling the reusable workflow in `winterchill-trading/infra`.
- To check a run: `gh run list --limit 1`, then at most one `gh run watch <id> --exit-status`.
