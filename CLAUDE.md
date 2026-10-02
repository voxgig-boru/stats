# CLAUDE.md

This repository is the `Stats` statistics library, written in boru —
descriptive, inferential, and matrix statistics exposed as the single
`Stats` namespace plus a streaming `Summary` accumulator.

## Using the library

See @AGENTS.md for how to call the `Stats` API correctly from boru — the
calling convention, the full API, copy-paste idioms, and the common
mistakes to avoid. Every example there was re-run against boru main @
`64c5ab2` (2026-10-01).

## Working on this repository

- A SessionStart hook (`.claude/settings.json` →
  `.claude/hooks/session-start.sh`) builds `boru` from boru-lang/boru
  **main** HEAD (`cmd/go` → `./boru`) in remote sessions, so a fresh session
  can run the suites. Locally, build it once from source (there is no tagged
  release and `go install …@latest` is blocked by replace directives) — see
  [docs/how-to.md](docs/how-to.md#install-and-run-boru).
- Tests live in `test/`, named `<subject>_<unit|prop>_<test|spec>.aql` plus a
  `stats_smoke_test.aql`: `_test` = imperative (`Test.test`/`Test.check-prop`),
  `_spec` = declarative spec; `unit` = example-based, `prop` = property-based.
  Each assertion-bearing suite ends by asserting `Test.fail-count` is `0` and
  prints `all green`. Exact-valued statistics are asserted directly; the
  irrational ones (stddev, correlation, the normal CDF) are tolerance-checked.
  Suites import the library as `"../stats.aql"` (relative imports resolve
  against the importing file) and import it **before** `boru:test` (an
  upstream type-identity defect otherwise breaks every Summary-returning
  word — see `dx-report.md`).
- One execution path: `boru X` compiles to bytecode and runs on the VM
  (after a static pre-flight check), or fails with `compile_failed`. The
  old `--compile` / `--force-compile` / `--no-compile` flags are retired,
  so "a suite runs" means "a suite fully compiles". Never use `-no-check`
  to get green.
- `test/divergence/run.sh` is the gate: every suite must exit 0 under
  `boru X` (and print `all green`), and `boru check` must report 0 errors on
  every suite and on `stats.aql`. It builds its own boru at main HEAD (via a
  codeload tarball, so it works even where raw `git clone` of boru is
  blocked); `BORU=/path/to/boru test/divergence/run.sh` reuses a binary.
  See its `README.md`.
- The library tracks boru **main** (no pinned commit): CI, the hook and the
  harness all resolve main HEAD at run time. Last verified against boru main
  @ `64c5ab2` (2026-09-30). Known boru-runtime gotchas, the upstream defects
  worked around, and the migration notes are in `dx-report.md`.
- Forking this repo to start a new boru library? See `TEMPLATE.md` on the
  template branch (this instantiated copy has removed it).
