# test: lightspark-client tests

- `test_grid.ml`, `test_lightning.ml`, `test_webhook.ml` and the unit tests run on redacted
  fixtures in `test/fixtures/grid` and `test/fixtures/graphql`. They run offline.
- `test/live/live_check.ml` reads credentials from the environment. Without them it prints one `skip`
  line. With `LIGHTSPARK_LIVE_WRITES=1` it creates a sandbox customer and moves a small amount; do
  not run it with writes unless the task asks.
- `test/tls/tls_check.ml` checks that expired, self-signed and wrong-host certificates are rejected.
  It skips when offline.
- Expected outputs print counts and statuses only. A test that prints an id is wrong; fix the test.
