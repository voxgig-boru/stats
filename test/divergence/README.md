# Multi-surface test gate: compiled run · check

This library's `.aql` suites are written once and must run clean on boru
main. `run.sh` runs every suite through both execution surfaces boru main
has, and checks the library module statically:

```bash
boru X            # compile to bytecode and run on the VM — the ONLY run path;
                  #   must exit 0 (and print `all green` where the suite asserts)
boru check X      # static type-check — must report 0 errors
```

## Why there is no interpreter / `--compile` column any more

Until 2026-09 boru had two engines — a tree-walking interpreter and a
bytecode compiler that silently fell back to it — and this harness compared
them (`boru --no-compile X` against `boru --compile X`, plus a
`--force-compile` coverage line). **Since boru main 2026-09-19 there is one
execution path**: a program compiles to bytecode and runs on the VM, or it
fails loudly with `[boru/compile_failed] … this is a compiler defect`. There
is no interpreter fallback, and `--compile`, `--force-compile`,
`--no-compile` and the `BORU_COMPILE` / `BORU_FORCE_COMPILE` /
`BORU_NO_COMPILE` env vars are **retired** (passing one is a usage error). So
"the suite runs" now *means* "the suite fully compiles", and those columns
were dropped — there is nothing left to diverge from.

`boru X` also runs the static pre-flight check by default (a check error
blocks the run). The harness never passes `-no-check`.

## Running it

```bash
test/divergence/run.sh                          # builds boru @ main HEAD (cached)
BORU=~/.local/bin/boru test/divergence/run.sh   # use an existing binary
BORU_REF=<sha> test/divergence/run.sh           # build a specific boru commit
```

Without `BORU`, `run.sh` builds its own boru at boru-lang/boru **main HEAD**
(resolved at run time, cached by SHA in `~/.cache/boru-divergence`), so it
never depends on whatever boru is on `PATH`. It fetches the source as a
codeload tarball (curl), so it builds even where raw `git clone` of
boru-lang/boru is blocked, and builds the CLI from `cmd/go` (`./boru`);
needs `go` + network for the one-time build. Output:

```
  MODULE                        CHECK
  stats.aql                     ok

  SUITE                         RUN                     CHECK
  stats_unit_test.aql           ok                      ok
  stats_unit_spec.aql           ok                      ok
  stats_prop_test.aql           ok                      ok
  stats_prop_spec.aql           ok                      ok
  stats_smoke_test.aql          ok                      ok
```

A `RUN` cell reads `COMPILE_FAILED` when boru refused to compile the suite
(an upstream compiler defect), `FAIL(exit N)` for any other non-zero exit,
and `FAIL(no all green)` when an assertion-bearing suite exited 0 but its
last output line is not `all green`. Every suite is assertion-bearing
except those listed in `run.sh`'s `NO_ASSERT` (the smoke suite), so a suite
that loses its tail assertion, or prints residue after `all green`, fails. The script exits non-zero on any of those or on any
check **error** (warnings and infos are reported by `boru check` but do not
gate).

## Background: what this guards against

The original reason for this harness was a byte-compiler miscompile that
escaped the "identical to the interpreter" promise (a compiled `each` body
once dropped a block-local binding). With a single compiled path such a bug
now shows up as a wrong answer in a suite or as a `compile_failed`, which
this gate catches directly; the upstream compiler defects hit during the
migration to boru main @ 64c5ab2 — and the library rewrites that avoid them —
are listed in [`dx-report.md`](../../dx-report.md#migration-to-boru-main--64c5ab2-2026-10-01).

### Wiring it into CI

`run.sh` is self-contained; the `divergence` job in
`.github/workflows/test.yml` already calls it:

```yaml
  divergence:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.24'
      - run: test/divergence/run.sh
```

The workflow needed no functional change for boru main: it already builds
boru at main HEAD from `cmd/go` (`./boru`) and invokes none of the retired
flags. Its comments and this job's step label ("interpreter / check /
byte-compiler agreement") still describe the old three-surface comparison
and a pinned `BORU_REF`; refreshing that text means editing
`.github/workflows/test.yml`, which needs a token with `workflow` scope, so
it was left for a maintainer. The behaviour is already correct.
