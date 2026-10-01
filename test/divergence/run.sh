#!/usr/bin/env bash
# Run every test suite (and the library module) through the two boru
# surfaces that exist on boru main, and fail on any error:
#
#   run     boru X          compile to bytecode and run on the VM — the ONLY
#                           execution path (see below); must exit 0, and an
#                           assertion-bearing suite must print `all green`
#   check   boru check X    static type-check; must report 0 errors
#
# Single-path model. Since boru main 2026-09-19 a program compiles to
# bytecode and runs on the VM, or it fails with `[boru/compile_failed] …
# this is a compiler defect`. There is no interpreter fallback any more, and
# the flags this harness used to compare (`--compile`, `--force-compile`,
# `--no-compile`, and the BORU_COMPILE / BORU_FORCE_COMPILE / BORU_NO_COMPILE
# env vars) are RETIRED — passing one is a usage error. The old INTERPRETER /
# BYTECODE / force-compile-coverage columns therefore have nothing left to
# compare: "the suite runs" now *means* "the suite fully compiles". What
# remains to gate is that every suite runs green compiled and checks clean.
#
# `boru X` also runs the static pre-flight check by default (a check error
# blocks the run); this harness never passes `-no-check`.
#
# The harness builds its OWN boru at boru-lang/boru main HEAD (resolved at run
# time, cached by SHA under ~/.cache/boru-divergence), so it never depends on
# whatever boru is on PATH. The source is fetched as a codeload tarball
# (curl), so it builds even where a raw `git clone` of boru-lang/boru is
# blocked; needs `go` + network for the one-time build. Overrides:
#
#   BORU=/path/to/boru      use an existing binary; skip the fetch + build
#   BORU_REF=<sha>          build this boru commit instead of main HEAD
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

MODULES="
stats.aql
"

SUITES="
test/stats_unit_test.aql
test/stats_unit_spec.aql
test/stats_prop_test.aql
test/stats_prop_spec.aql
test/stats_smoke_test.aql
"

log() { echo "[divergence] $*"; }

# --- locate or build boru -------------------------------------------------
if [ -n "${BORU:-}" ]; then
  [ -x "$BORU" ] || { echo "error: BORU=$BORU is not an executable." >&2; exit 1; }
else
  BORU_REF="${BORU_REF:-$(git ls-remote https://github.com/boru-lang/boru.git main | cut -f1)}"
  [ -n "$BORU_REF" ] || { echo "error: could not resolve boru main HEAD (network?); set BORU=/path/to/boru." >&2; exit 1; }
  CACHE="$HOME/.cache/boru-divergence"
  BORU="$CACHE/boru-$BORU_REF"
  if [ ! -x "$BORU" ]; then
    command -v go >/dev/null 2>&1 || { echo "error: Go toolchain not found." >&2; exit 1; }
    log "building boru @ $BORU_REF (one-time; cached) …"
    src="$(mktemp -d)"
    curl -fsSL "https://codeload.github.com/boru-lang/boru/tar.gz/$BORU_REF" \
      | tar -xz -C "$src" --strip-components=1 || { echo "error: fetch/extract failed." >&2; exit 1; }
    mkdir -p "$CACHE"
    # The CLI's main package is cmd/go/boru (the binary is `boru`, not `aql`).
    ( cd "$src/cmd/go" && GOWORK=off GOFLAGS=-mod=mod go build \
        -ldflags "-X github.com/boru-lang/boru/cmd/go.Version=$BORU_REF" \
        -o "$BORU" ./boru ) || { echo "error: build failed." >&2; exit 1; }
    rm -rf "$src"
  fi
fi
log "boru: $("$BORU" -version)"
echo

cd "$REPO"
fail=0

# check_errors FILE -> prints the error count from `boru check` (or `?`).
check_errors() {
  local n
  n="$("$BORU" check "$1" 2>&1 | grep -oE '[0-9]+ error\(s\)' | grep -oE '[0-9]+' | tail -1)"
  echo "${n:-?}"
}

# --- modules: check only (a module has no top-level program to run) ------
log "modules — boru check must report 0 errors:"
printf '  %-28s  %s\n' MODULE CHECK
for m in $MODULES; do
  errs="$(check_errors "$m")"
  if [ "$errs" = 0 ]; then c_col="ok"; else c_col="FAIL($errs err)"; fail=1; fi
  printf '  %-28s  %s\n' "$m" "$c_col"
done
echo

# --- suites: run (compiled) + check ---------------------------------------
log "suites — boru X must exit 0 (and print \`all green\` where asserted); boru check X must report 0 errors:"
printf '  %-28s  %-22s  %s\n' SUITE RUN CHECK
for s in $SUITES; do
  name="$(basename "$s")"

  out="$("$BORU" "$s" 2>&1)"; rc=$?
  if [ $rc -ne 0 ]; then
    if printf '%s\n' "$out" | grep -q 'compile_failed'; then r_col="COMPILE_FAILED"; else r_col="FAIL(exit $rc)"; fi
    fail=1
  elif grep -q '"all green"' "$s" && ! printf '%s\n' "$out" | grep -qx 'all green'; then
    r_col="FAIL(no all green)"; fail=1
  else
    r_col="ok"
  fi

  errs="$(check_errors "$s")"
  if [ "$errs" = 0 ]; then c_col="ok"; else c_col="FAIL($errs err)"; fail=1; fi

  printf '  %-28s  %-22s  %s\n' "$name" "$r_col" "$c_col"
  if [ "$r_col" != ok ]; then
    printf '%s\n' "$out" | grep -E 'error|FAIL|compile_failed' | head -5 | sed 's/^/      /'
  fi
done

echo
if [ "$fail" = 0 ]; then
  log "PASS — every suite runs green compiled and every file checks with 0 errors."
else
  log "FAIL — a suite failed to compile/run, or a file has check errors."
fi
exit $fail
