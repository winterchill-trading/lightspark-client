# bin: lightspark CLI

`lightspark.ml` is the `lightspark` executable. Subcommands: `account`, `nodes`, `wallets`,
`transactions`, `invoice`, `fund-node`, `grid ...` (customers, accounts, transfers, quotes) and
`webhook ...` (signature checks). Output is JSON, or sexps with `-sexp`.

Rules:

- Default to sandbox. A command that moves money must go through the write guards in `lib/`.
- Read configuration from the environment only; never accept a secret as a flag.
- Print status and counts, not account ids or personal data, in examples and docs.
