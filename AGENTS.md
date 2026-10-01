# AGENTS.md — using the `Stats` library

Guidance for an AI coding agent calling this statistics library from an
boru project. Every code block below is verified against boru main @
`64c5ab2` (2026-09-30; executed from a scratch file on 2026-10-01). If you
read nothing else, read [The one calling rule](#the-one-calling-rule) and
[Common mistakes](#common-mistakes).

## What it is

Descriptive, inferential, and matrix statistics. The public surface is
the `Stats` namespace plus the `Summary` type. There are two ways in:

- **Pure functions over a List** — `Stats.mean [1 2 3] end`. Simple,
  and the only way to get order statistics (median, quantile, mode).
- **A streaming `Summary` accumulator** — build one, `push` values into
  it, `merge` two of them, `encode`/`decode` it. It keeps running moments
  (Welford/Pébay), so mean/variance/skewness/kurtosis cost one pass and a
  merge is O(1). The same descriptive words read a `Summary` directly.

The **dataset** words take an `boru:matrix-util` `Matrix` whose rows are
observations and columns are variables.

## Import

```boru
import "./stats.aql"
```

- A relative path is resolved **against the importing file's own
  directory** (for `boru X` and `boru check X` alike), not the working
  directory — a suite in `test/` imports `"../stats.aql"`.
- No `end` is needed after `import` (a trailing `end` is harmless).
- **Import `./stats.aql` before `boru:test`.** On boru main @ `64c5ab2`, a
  script that imports `boru:test` *first* hits an upstream type-identity
  defect: every word returning a `Summary` raises
  `type_error: … expected Summary, got Summary`. Importing the library
  first avoids it (see `dx-report.md`, "Migration to boru main @ 64c5ab2").
- Do **not** import `boru:math-util`, `boru:array-util`, `boru:matrix-util`,
  or `boru:struct-util` for the library's sake — `stats.aql` imports its
  own dependencies. **But** if *you* construct a `Matrix` to pass to the
  dataset words, add `import "boru:matrix-util"` to **your** script: the
  library's import does not re-export the `MatrixUtil` binding to callers.

## The one calling rule

boru is not C/Python/JS. There is no `f(a, b)` and no `obj.method(a)`.
A `Stats` call is written **forward** — the verb first, then the
arguments — with the **receiver last**:

```
Stats.verb arg1 arg2 … receiver end
```

— the **verb comes first**, then the arguments, and the **receiver** (the
thing the word reads or mutates) is the **LAST** argument. The call is
**terminated with `end`** (or wrapped in parens). Without a terminator
the verb can swallow whatever token follows it and you get wrong results
or a dispatch error.

For the pure words the receiver is just the data, and it's the only/last
arg anyway:

```boru
def xs [2 4 4 4 5 5 7 9]
print ((Stats.mean   xs end)) end    # => 5.0
print ((Stats.median xs end)) end    # => 4.5
```

For the streaming accumulator words the receiver is the `Summary`, so the
value(s) come **first** and the `Summary` comes **last** —
`Stats.push value s`, `Stats.push-all values s`, `Stats.merge other a`.
Receiver-last means the `Summary` also binds when it flows in from the
**left**, so `Stats.push value s` and `s Stats.push value` are identical.
The **only** shape that misbinds is *receiver-first-all-forward*. For
`push`/`push-all` (`Stats.push s value`) boru main now refuses it loudly —
`boru check` (and so `boru X`, which checks first) reports
`uncalled_function: call to 'stat-push' matched no signature`. For
`merge`, whose two arguments are both `Summary`, `Stats.merge a b` still
binds **silently** — it folds `a` into `b` and mutates `b` — so write
`Stats.merge other receiver` deliberately.

`(… )` parentheses count as a terminator, so `(Stats.mean xs)` is fine
too; use `end` for top-level statements that aren't already wrapped.
(The core array words `each`/`fold`, indexing `get`, and the matrix
accessors `MatrixUtil.row`/`col` read their subject from the *stack* and
so stay subject-first — `xs get (i)`, `mat MatrixUtil.col j` — that is
their native form.)

## API reference (exact call shapes)

Every **descriptive** word accepts either a `List` of numbers or a
`Summary`. The **order-statistic** words take a `List` only.

### Accumulator — the streaming `Summary`

| Call | Returns | Notes |
|------|---------|-------|
| `Stats.summary xs end` | `Summary` | Build from a List (`[]` ⇒ empty). |
| `Stats.push x s end` | the **same** `s` (mutated) | Add one observation. Value first, accumulator `s` **last** (or pipe `s Stats.push x`). |
| `Stats.push-all xs s end` | the **same** `s` (mutated) | Add every element of a List. List first, accumulator `s` **last**. |
| `Stats.merge b a end` | the **same** `a` (mutated) | Fold `b`'s moments into `a`; receiver `a` **last**. Always compatible. |
| `Stats.encode s end` | `String` | jsonic snapshot of the moments. |
| `Stats.decode text end` | `Summary` | Rebuild from a snapshot; bad text raises `bad_payload`. |

### Descriptive (List **or** Summary)

| Call | Returns | Notes |
|------|---------|-------|
| `Stats.count x end` | `Integer` | Observation count; empty ⇒ `0`. |
| `Stats.sum x end` | `Float` | Total. |
| `Stats.mean x end` | `Float` | Needs ≥ 1 value. |
| `Stats.variance x end` | `Float` | **Sample** (n-1). Needs ≥ 2 values. |
| `Stats.pvariance x end` | `Float` | **Population** (n). |
| `Stats.stddev x end` / `Stats.pstddev x end` | `Float` | Sample / population std dev. |
| `Stats.min x end` / `Stats.max x end` / `Stats.range x end` | `Float` | Extremes and `max - min`. |
| `Stats.skewness x end` | `Float` | Biased g1. |
| `Stats.kurtosis x end` | `Float` | Biased **excess** g2. |

### Order statistics (List only)

| Call | Returns | Notes |
|------|---------|-------|
| `Stats.median xs end` | `Float` | |
| `Stats.quantile xs q end` | `Float` | `q` in `[0,1]`, linear interpolation (type-7). |
| `Stats.iqr xs end` | `Float` | Q3 − Q1. |
| `Stats.mode xs end` | `Float` | Most frequent; smallest value on a tie. |

### Bivariate (two Lists)

| Call | Returns | Notes |
|------|---------|-------|
| `Stats.covariance xs ys end` | `Float` | **Sample**. |
| `Stats.pcovariance xs ys end` | `Float` | **Population**. |
| `Stats.correlation xs ys end` | `Float` | Pearson r in `[-1, 1]`. |
| `Stats.linreg xs ys end` | `Map` | `{slope, intercept, r, r2}` — `xs` predictor, `ys` response. |

### Distributions / scores

| Call | Returns | Notes |
|------|---------|-------|
| `Stats.zscores xs end` | `List` | Sample-standardised values. |
| `Stats.normal-pdf x {mu, sigma} end` | `Float` | `sigma > 0`. |
| `Stats.normal-cdf x {mu, sigma} end` | `Float` | erf approximation (abs error ≈ 1.5e-7). |

### Matrix / dataset (rows = observations, cols = variables)

| Call | Returns | Notes |
|------|---------|-------|
| `Stats.col-means mat end` | `List` | Per-column means. |
| `Stats.col-variances mat end` / `Stats.col-stddevs mat end` | `List` | Per-column **sample** variance / std dev. |
| `Stats.cov-matrix mat end` | `Matrix` | **Sample** covariance matrix. Needs ≥ 2 rows. |
| `Stats.cor-matrix mat end` | `Matrix` | Correlation matrix. |
| `Stats.standardize mat end` | `Matrix` | Each column z-scored. |
| `Stats.ols x ys end` | `List` | Least-squares coefficients (`x` = design Matrix). |

Construct `Summary` values **only** through `Stats.summary`. Treat
`Summary` fields as read-only; mutate through the namespace words.

The unqualified `variance`/`stddev`/`covariance` are **sample**
statistics (Bessel's n-1 correction); the `p`-prefixed ones are
**population**.

Errors carry a code and message: catch with `do […] error […]`; inside the
handler the Error is on the stack, so read `dot code` / `dot message`
(`dot` quotes the bare field name; or bind it, `var [[e] e.code]`).
`get` evaluates its key, so a bare `get code` is an
`undefined word: code` error. Codes: `bad_input`
(empty/too-few data, a quantile out of `[0,1]`, a non-positive `sigma`,
mismatched lengths), `needs_data` (an order-statistic word called on a
`Summary`), `singular` (`Stats.ols` has no unique solution),
`bad_payload` (bad `Stats.decode` text).

## Copy-paste idioms (all verified)

Descriptive statistics over a List:

```boru
import "./stats.aql"
def xs [2 4 4 4 5 5 7 9]
print ((Stats.mean     xs end)) end   # => 5.0
print ((Stats.variance xs end)) end   # => 4.571428571428571 (sample)
print ((Stats.median   xs end)) end   # => 4.5
print ((Stats.quantile xs 0.9 end)) end   # => 7.6
```

The streaming accumulator — build, push, query:

```boru
def s (Stats.summary [1 2 3 4] end)
def _ (Stats.push-all [5 6 7 8] s end)
def _2 (Stats.push 9 s end)
print ((Stats.count s end)) end       # => 9
print ((Stats.mean  s end)) end       # => 5.0
```

Merge is O(1) and gives the same answer as pooling the data — useful for
parallel/streaming aggregation:

```boru
def a (Stats.summary [1 2 3 4] end)
def b (Stats.summary [5 6 7 8] end)
def merged (Stats.merge b a end)
print ((Stats.mean     merged end)) end   # => 4.5
print ((Stats.variance merged end)) end   # => 6.0
```

Persist and reload a Summary through the snapshot string:

```boru
def snap (Stats.encode merged end)
def back (Stats.decode snap end)
print ((Stats.mean back end)) end          # => 4.5
```

Bivariate and regression:

```boru
def x [1 2 3 4 5]
def y [2 4 5 4 5]
print ((Stats.correlation x y end)) end    # => 0.7745966692414833
def lr (Stats.linreg x y end)
print (lr.slope) end                       # => 0.6
print (lr.intercept) end                   # => 2.2
```

Dataset statistics over a Matrix (import matrix-util yourself):

```boru
import "boru:matrix-util"
import "./stats.aql"
def mat (MatrixUtil.create [[1 2] [3 6] [5 10] [7 12]])
print ((Stats.col-means mat end)) end      # => [4.0, 7.5]
def cov (Stats.cov-matrix mat end)         # => Matrix(2x2)
```

Multiple linear regression via OLS (prepend a 1s column for the
intercept):

```boru
import "boru:matrix-util"
import "./stats.aql"
def design (MatrixUtil.create [[1 1] [1 2] [1 3] [1 4]])
def coef (Stats.ols design [2 3 5 8] end)
print (coef) end                           # => [-0.5, 2.0]  (intercept, slope)
```

Guard a misuse (an order statistic on a Summary raises `needs_data`):

```boru
def s (Stats.summary [1 2 3] end)
def code (do [Stats.median s end] error [ dot code ])
print (code) end                           # => needs_data
```

## Common mistakes

| ✗ Don't write | ✓ Write | Why |
|---------------|---------|-----|
| `Stats.mean(xs)` | `Stats.mean xs end` | No `f(a,b)` syntax in boru. |
| `xs.mean()` | `Stats.mean xs end` | No method-call syntax. |
| `Stats.mean xs` (no terminator, mid-expression) | `Stats.mean xs end` | The verb swallows the next token without `end`/parens. |
| `Stats.median s end` on a Summary | pass the raw **List** to `median` | Order statistics need the data; a `Summary` raises `needs_data` (inside `do […]`). Written directly at top level, the pre-flight `boru check` already rejects it — with a misleading `type_error: require-list: return value 1: expected List, got Summary` (an upstream checker false positive; see `dx-report.md`). |
| treat `Stats.variance` as population variance | `Stats.pvariance` for population | Bare `variance`/`stddev` are **sample** (n-1). |
| keep a pre-`push` copy of a Summary as "before" | `push`/`merge` mutate in place | The argument and the returned value are the **same** object. |
| `e get code` / `lr get slope` (a bare field name after `get`) | `e.code`, `lr.slope`, or `dot code` in a handler | `get` **evaluates** its key (`xs get i` uses the value of `i`), so a bare field name is an `undefined word`. Use dot access, or quote the name with `/q`. |
| pass a Stats word as data bare: `[Stats.mean Stats.median]`, or `myfn Stats.mean xs` | `[Stats.mean/v Stats.median/v]`, `myfn Stats.mean/v xs` | A bare name holding a function **calls** wherever it appears (`uncalled_function` / `no_signature` at check); `/v` hands over the function value. (`xs each Stats.mean` happens to work — `each` takes a bare word as its body — but `/v` is always safe.) |
| `import "boru:test"` *before* `import "./stats.aql"` | import `./stats.aql` first | Upstream type-identity defect on boru main @ `64c5ab2`: Summary-returning words raise `expected Summary, got Summary`. |
| call the dataset words without `import "boru:matrix-util"` in your script | add the import yourself | The library's deps are not re-exported to callers. |
| `make Summary {…}` | `Stats.summary xs end` | Construct only via `Stats.summary`. |
| `"label" print (v) print` (or `"a" print` on one line, `"b" print` on the next) | `print (value)`, one per statement | `print` collects a forward argument and a line break is not a barrier; chains print out of order. |

## Where to look next

- `docs/reference.md` — full signatures, semantics, complexity.
- `api.json` — the same API as a machine-readable manifest.
- `docs/how-to.md` — task recipes (summarise, merge, regress, persist).
- `docs/tutorial.md` — a guided first session.
- `test/stats_smoke_test.aql` — a complete, runnable worked example.
- `dx-report.md` — boru-runtime gotchas observed while building this module.
