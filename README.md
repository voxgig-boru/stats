# stats

A **statistics library** implemented in
[boru](https://github.com/boru-lang/boru) — descriptive, inferential, and
matrix statistics behind a single `Stats` namespace, plus a streaming
`Summary` accumulator. It builds on boru's numeric types and the
`boru:matrix-util` / `boru:math-util` modules.

```boru
import "./stats.aql"

def xs [2 4 4 4 5 5 7 9]
print ((Stats.mean   xs end)) end   # => 5.0
print ((Stats.median xs end)) end   # => 4.5
print ((Stats.stddev xs end)) end   # => 2.138089935299395  (sample)
```

> **Calling this library from an AI coding agent?** Read
> **[AGENTS.md](AGENTS.md)** first — the exact boru calling convention,
> verified idioms, and common mistakes. (Claude Code auto-loads it via
> `CLAUDE.md`; a portable skill lives in
> [`.claude/skills/stats-aql`](.claude/skills/stats-aql/SKILL.md).)

## Two ways in

**Pure functions over a List** — the simplest path, and the only way to
get order statistics:

```boru
print ((Stats.variance [1 2 3 4 5] end)) end       # => 2.5 (sample)
print ((Stats.quantile [1 2 3 4 5] 0.9 end)) end   # => 4.6
```

**A streaming `Summary` accumulator** — keeps running Welford moments, so
mean/variance/skewness/kurtosis cost one pass and two summaries merge in
O(1) (ideal for parallel or streaming aggregation):

```boru
def a (Stats.summary [1 2 3 4] end)
def b (Stats.summary [5 6 7 8] end)
def merged (Stats.merge b a end)
print ((Stats.mean merged end)) end                # => 4.5
```

The dataset words operate on an `boru:matrix-util` Matrix (rows =
observations, columns = variables) — column means, covariance and
correlation matrices, standardization, and ordinary least squares.

## Documentation

The docs are organised into four modes, each serving a different need:

| | Mode | Read this when you want to… |
|--|------|----------------------------|
| 🎓 | **[Tutorial](docs/tutorial.md)** | learn by working a first session step by step |
| 🔧 | **[How-to guides](docs/how-to.md)** | accomplish a specific task (summarise, merge, regress, persist…) |
| 📖 | **[Reference](docs/reference.md)** | look up exact words, signatures, and return types |
| 💡 | **[Explanation](docs/explanation.md)** | understand how it works and why it's built this way |

New here? Read the [Tutorial](docs/tutorial.md). Already know the domain
and just want the API? Jump to the [Reference](docs/reference.md).

## The `Stats` API at a glance

| Group | Words |
|-------|-------|
| Accumulator | `Stats.summary xs` · `Stats.push x s` · `Stats.push-all xs s` · `Stats.merge b a` · `Stats.encode s` · `Stats.decode text` |
| Descriptive (List or Summary) | `mean` · `sum` · `count` · `min` · `max` · `range` · `variance`/`pvariance` · `stddev`/`pstddev` · `skewness` · `kurtosis` |
| Order statistics (List) | `median` · `quantile xs q` · `iqr` · `mode` |
| Bivariate | `Stats.covariance xs ys` · `pcovariance` · `correlation` · `linreg` |
| Distributions | `Stats.zscores xs` · `Stats.normal-pdf x {mu, sigma}` · `normal-cdf` |
| Matrix / dataset | `col-means` · `col-variances` · `col-stddevs` · `cov-matrix` · `cor-matrix` · `standardize` · `Stats.ols x ys` |

Every call is verb-first and ends with `end`:
`Stats.verb data args… end`. Unqualified `variance`/`stddev`/
`covariance` are **sample** statistics (n-1); the `p`-prefixed ones are
**population**. Full details are in the [Reference](docs/reference.md).

## For AI coding agents

If an agent will call this library, point it at **[AGENTS.md](AGENTS.md)**
— the exact boru calling convention, verified idioms, and the common
mistakes to avoid.

To make that guidance available in *another* project that uses this
library, install the bundled skill either way:

- **Copy the skill** — drop
  [`.claude/skills/stats-aql/`](.claude/skills/stats-aql/SKILL.md)
  into that project's `.claude/skills/` (or your `~/.claude/skills/`). It
  loads on demand whenever `Stats` calls appear.
- **Install the plugin** — this repo is also a plugin marketplace:

  ```
  /plugin marketplace add voxgig-boru/stats
  /plugin install stats-aql@voxgig-boru
  ```

Working inside *this* repo, Claude Code picks the guidance up
automatically via `CLAUDE.md` (which imports `AGENTS.md`) and the bundled
skill.

## Project layout

```
stats.aql                  the library (the Stats namespace + Summary type)
AGENTS.md                  agent guide: how to call this library correctly
test/stats_unit_test.aql   example-based unit tests — direct (Test.test)
test/stats_unit_spec.aql   example-based unit tests — declarative spec format
test/stats_prop_test.aql   property-based tests — direct (Test.check-prop)
test/stats_prop_spec.aql   property-based tests — declarative spec format
test/stats_smoke_test.aql  end-to-end smoke run over every public word
docs/                      documentation (above)
test/divergence/run.sh     the gate: every suite runs green compiled + 0 check errors
dx-report.md               developer-experience notes (verified: boru main @ 64c5ab2)
proposals/                 language proposals raised from this module's DX
```

Test files follow a consistent naming convention: `_test.aql` for
direct tests (unit or property), `_spec.aql` for declarative specs (unit
or property).

## Running it

Build the `boru` CLI from boru main, then run any script or test — see
[How-to → Install and run](docs/how-to.md#install-and-run-boru) and
[Run the tests](docs/how-to.md#run-the-tests):

```bash
boru test/stats_unit_test.aql   # unit tests — direct
boru test/stats_unit_spec.aql   # unit tests — declarative spec format
boru test/stats_prop_test.aql   # property tests — direct
boru test/stats_prop_spec.aql   # property tests — declarative spec format
boru test/stats_smoke_test.aql  # end-to-end smoke run
```

`boru X` compiles the program to bytecode and runs it on the VM (the only
execution path on boru main), after a static pre-flight check. A GitHub
Actions workflow ([`.github/workflows/test.yml`](.github/workflows/test.yml))
builds boru from the current main HEAD and runs every suite, plus the
[`test/divergence/run.sh`](test/divergence/README.md) gate (every suite runs
green compiled and every file checks with 0 errors) and a `consistency` job
(agent-skill drift, JSON manifests) on each push and pull request.

## License

See [LICENSE](LICENSE).
