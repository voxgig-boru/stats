# Reference

Technical description of the `Stats` module's public surface. This page
is information-oriented: it states what each word is, its call shape,
arguments, and what it returns. For *why* the library behaves the way it
does, see [Explanation](explanation.md); for goal-directed recipes, see
the [How-to guides](how-to.md).

> **AI agents:** [AGENTS.md](../AGENTS.md) condenses the calling
> convention, idioms, and common mistakes for machine use; `api.json` is
> the same API as a machine-readable manifest.

The module exports a single namespace, `Stats`, plus the `Summary` type.
Import it with:

```boru
import "./stats.aql"
```

(No `end` is required after `import`; a trailing `end` is harmless. A
relative import path resolves against the importing file's own
directory, not the working directory. Import the library **before**
`boru:test` — see the note under [Errors at a glance](#errors-at-a-glance).) A consuming script does **not** need to import
`boru:math-util`, `boru:array-util`, `boru:matrix-util`, or
`boru:struct-util` itself — `stats.aql` imports them internally. The one
exception: scripts that build a `Matrix` to pass to the dataset words
must `import "boru:matrix-util"` themselves, because that binding is not
re-exported.

---

## Calling convention

Every operation is a forward-dispatched word: the **verb comes first**,
then the data, then any extra arguments, and the call is **terminated
with `end`** (or wrapped in parentheses), e.g. `Stats.mean xs end` or
`(Stats.quantile xs 0.9)`. Without a terminator the word collects the
following token as an argument. This is general boru forward-precedence
behaviour, not specific to this module. There is no `f(x)` or `x.f()`
syntax.

Inputs may be Integer or Float; all arithmetic is done in Float, so
results are Float (`count` returns Integer). `get` evaluates its key, so
`xs get i` and `xs get (i)` both index by the value of `i`; read a named
field with dot access (`fit.slope`), not `fit get slope`.

To pass a `Stats` word itself as a value (to `each`, say), write
`Stats.mean/v`: a bare name that holds a function **calls** wherever it
appears, and `/v` hands over the function instead.

---

## Input polymorphism

The **descriptive** words (`count`, `sum`, `mean`, `variance`,
`pvariance`, `stddev`, `pstddev`, `min`, `max`, `range`, `skewness`,
`kurtosis`) accept **either a List of numbers or a `Summary`**. The
**order-statistic** words (`median`, `quantile`, `iqr`, `mode`) and
`zscores` need the raw data and take a **List only** — calling one on a
Summary raises `needs_data`. The **bivariate** words (`covariance`,
`pcovariance`, `correlation`, `linreg`) are typed `[xs:List ys:List]`, so a
Summary there matches no signature and `boru check` (which every `boru X`
runs first) rejects the call with `uncalled_function`.

## Sample vs population

The unqualified `variance`/`stddev`/`covariance` are **sample**
statistics (divide by `n - 1`). The `p`-prefixed `pvariance`/`pstddev`/
`pcovariance` are **population** statistics (divide by `n`). The
per-column matrix words and `cov-matrix` are sample statistics.

---

## Types

### `Summary`

A sealed `class` instance — a streaming accumulator of running central
moments (Welford / Pébay). Fields:

| Field  | Type    | Meaning                                          |
|--------|---------|--------------------------------------------------|
| `n`    | Integer | Number of observations seen                      |
| `mean` | Float   | Running mean                                     |
| `m2`   | Float   | Central-moment sum Σ(x-mean)²                    |
| `m3`   | Float   | Central-moment sum Σ(x-mean)³                    |
| `m4`   | Float   | Central-moment sum Σ(x-mean)⁴                    |
| `min`  | Float   | Smallest observation                             |
| `max`  | Float   | Largest observation                              |

Instances are created **only** through `Stats.summary` (or rebuilt by
`Stats.decode`). Treat the fields as read-only; update exclusively
through the namespace words. Variance, skewness, and kurtosis are
derived from `m2`/`m3`/`m4` on demand. An empty Summary has `n = 0`;
`min`/`max` are seeded by the first observation.

---

## Accumulator words

### `Stats.summary`

Build a streaming accumulator from a List of numbers.

| | |
|--|--|
| **Call**    | `Stats.summary xs end` |
| **Args**    | `xs: List` |
| **Returns** | `Summary` (`[]` gives an empty Summary) |

### `Stats.push`

Add one observation. Welford update; **mutates** the Summary and returns
the same object.

| | |
|--|--|
| **Call**    | `Stats.push x s end` (value first, accumulator last; `s Stats.push x end` also binds) |
| **Args**    | `x: Number`, `s: Summary` |
| **Returns** | the same `Summary`, mutated |

### `Stats.push-all`

Add every element of a List.

| | |
|--|--|
| **Call**    | `Stats.push-all xs s end` (list first, accumulator last; `s Stats.push-all xs end` also binds) |
| **Args**    | `xs: List`, `s: Summary` |
| **Returns** | the same `Summary`, mutated |

### `Stats.merge`

Combine the moments of `b` into `a` (parallel/Pébay combine).

| | |
|--|--|
| **Call**    | `Stats.merge b a end` (receiver `a` last; `a Stats.merge b end` also binds) |
| **Args**    | `b: Summary`, `a: Summary` |
| **Returns** | `a`, mutated to hold both |
| **Effect**  | `a` is mutated; `b` is unchanged. Always compatible (no parameters to disagree on). O(1). |

```boru
def a (Stats.summary [1 2 3 4] end)
def b (Stats.summary [5 6 7 8] end)
def _m (Stats.merge b a end)
print ((Stats.mean a end)) end   # => 4.5
```

### `Stats.encode`

Snapshot a Summary's moments as a jsonic String.

| | |
|--|--|
| **Call**    | `Stats.encode s end` |
| **Args**    | `s: Summary` |
| **Returns** | `String` (`{n, mean, m2, m3, m4, min, max}`) |

```boru
print ((Stats.encode (Stats.summary [1 2 3 4 5] end) end)) end
# => {n:5 mean:3.0 m2:10.0 m3:0.0 m4:34.0 min:1.0 max:5.0}
```

Round-trips through `Stats.decode`.

### `Stats.decode`

Rebuild a Summary from an `encode` snapshot.

| | |
|--|--|
| **Call**    | `Stats.decode text end` |
| **Args**    | `text: String` |
| **Returns** | `Summary` |
| **Errors**  | `bad_payload` when the text is unparseable or missing a field |

Whole-valued Float moments render with their decimal point (`10.0`) and
parse back as Float, so `decode` only coerces the count `n` to Integer.

---

## Descriptive words (List | Summary)

| Word | Call | Returns | Semantics / errors |
|------|------|---------|--------------------|
| `count`     | `Stats.count x end`     | Integer | Number of observations; empty ⇒ `0`. |
| `sum`       | `Stats.sum x end`       | Float   | Total of the observations. |
| `mean`      | `Stats.mean x end`      | Float   | Arithmetic mean. Needs ≥ 1 value (else `bad_input`). |
| `variance`  | `Stats.variance x end`  | Float   | **Sample** variance, `m2/(n-1)`. Needs ≥ 2 values. |
| `pvariance` | `Stats.pvariance x end` | Float   | **Population** variance, `m2/n`. Needs ≥ 1 value. |
| `stddev`    | `Stats.stddev x end`    | Float   | **Sample** standard deviation (√variance). |
| `pstddev`   | `Stats.pstddev x end`   | Float   | **Population** standard deviation. |
| `min`       | `Stats.min x end`       | Float   | Minimum observation. |
| `max`       | `Stats.max x end`       | Float   | Maximum observation. |
| `range`     | `Stats.range x end`     | Float   | `max - min`. |
| `skewness`  | `Stats.skewness x end`  | Float   | Biased sample skewness g1 `= (m3/n)/(m2/n)^1.5`. `bad_input` on zero-variance data. |
| `kurtosis`  | `Stats.kurtosis x end`  | Float   | Biased excess kurtosis g2 `= (m4/n)/(m2/n)^2 - 3`. `bad_input` on zero-variance data. |

`x` is a `List` or a `Summary`.

```boru
def s (Stats.summary [2 4 4 4 5 5 7 9] end)
print ((Stats.skewness s end)) end   # => 0.6562500000000001
print ((Stats.kurtosis s end)) end   # => -0.21875
print ((Stats.variance s end)) end   # => 4.571428571428571
```

---

## Order statistics (List only)

A Summary discards the raw data, so these require a `List`; a Summary
raises `needs_data`.

| Word | Call | Returns | Semantics / errors |
|------|------|---------|--------------------|
| `median`   | `Stats.median xs end`     | Float | The 0.5 quantile. |
| `quantile` | `Stats.quantile xs q end` | Float | `q` in `[0,1]`, linear interpolation (NumPy/R type-7). `q` out of range ⇒ `bad_input`. |
| `iqr`      | `Stats.iqr xs end`        | Float | Inter-quartile range, Q3 − Q1. |
| `mode`     | `Stats.mode xs end`       | Float | Most frequent value; smallest such value on a tie. |

```boru
print ((Stats.quantile [1 2 3 4 5] 0.25 end)) end   # => 2.0
```

---

## Bivariate words (two Lists)

Two equal-length Lists; mismatched lengths raise `bad_input`.

| Word | Call | Returns | Semantics / errors |
|------|------|---------|--------------------|
| `covariance`  | `Stats.covariance xs ys end`  | Float | **Sample** covariance. Needs ≥ 2 paired values. |
| `pcovariance` | `Stats.pcovariance xs ys end` | Float | **Population** covariance. |
| `correlation` | `Stats.correlation xs ys end` | Float | Pearson `r` in `[-1, 1]`. `bad_input` if a variable has zero variance. |
| `linreg`      | `Stats.linreg xs ys end`      | Map   | Simple regression of `ys` on `xs`: `{slope, intercept, r, r2}`. Predictor must have non-zero variance. |

```boru
def fit (Stats.linreg [1 2 3 4 5] [2 4 5 4 5] end)
print (fit.slope) end       # => 0.6
print (fit.intercept) end   # => 2.2
```

---

## Distribution / score words

| Word | Call | Returns | Semantics / errors |
|------|------|---------|--------------------|
| `zscores`    | `Stats.zscores xs end`               | List  | Sample-standardised `(x - mean)/stddev`. Zero stddev ⇒ `bad_input`. List only. |
| `normal-pdf` | `Stats.normal-pdf x {mu, sigma} end` | Float | Normal probability density at `x`. `sigma > 0` (else `bad_input`). |
| `normal-cdf` | `Stats.normal-cdf x {mu, sigma} end` | Float | Normal cumulative probability at `x`, via an Abramowitz–Stegun erf approximation (abs error ≈ 1.5e-7). `sigma > 0`. |

```boru
print ((Stats.normal-cdf 0 {mu: 0.0, sigma: 1.0} end)) end   # => 0.5000000005
print ((Stats.zscores [1 2 3] end)) end                      # => [-1.0, 0.0, 1.0]
```

---

## Matrix / dataset words

These take a `MatrixUtil` Matrix whose **rows are observations** and
**columns are variables**. The per-column words return a `List`;
`cov-matrix`/`cor-matrix`/`standardize` return a `Matrix`.

| Word | Call | Returns | Semantics / errors |
|------|------|---------|--------------------|
| `col-means`     | `Stats.col-means mat end`     | List   | Per-column means. |
| `col-variances` | `Stats.col-variances mat end` | List   | Per-column **sample** variances. |
| `col-stddevs`   | `Stats.col-stddevs mat end`   | List   | Per-column **sample** standard deviations. |
| `cov-matrix`    | `Stats.cov-matrix mat end`    | Matrix | **Sample** covariance matrix `(1/(n-1)) Xcᵀ Xc`. Needs ≥ 2 rows. |
| `cor-matrix`    | `Stats.cor-matrix mat end`    | Matrix | Correlation matrix derived from `cov-matrix`. |
| `standardize`   | `Stats.standardize mat end`   | Matrix | Each column z-scored (sample mean/stddev). |
| `ols`           | `Stats.ols x ys end`          | List   | Least-squares coefficients via `XᵀX b = Xᵀy`. Rows of `X` must match length of `ys` (else `bad_input`); a rank-deficient system raises `singular`. Prepend a 1s column for an intercept. |

```boru
import "boru:matrix-util"
import "./stats.aql"
def mat (MatrixUtil.create [[1 2] [3 6] [5 10] [7 12]])
print ((Stats.col-means mat end)) end                  # => [4.0, 7.5]
def design (MatrixUtil.create [[1 1] [1 2] [1 3] [1 4]])
print ((Stats.ols design [2 3 5 8] end)) end            # => [-0.5, 2.0]
```

---

## Errors at a glance

All failures raise coded errors; catch with `do […] error […]` and, in
the handler (where the Error is on the stack), read `dot code` /
`dot message` — or `e.code` on a bound error (dispatch on several codes
with `case`). A bare `get code` is an `undefined word: code` error,
because `get` evaluates its key.

| Code | Situation |
|------|-----------|
| `bad_input` | empty data, too few points for the statistic, a `quantile` `q` outside `[0,1]`, a non-positive sigma, mismatched vector lengths, or a zero-variance predictor |
| `needs_data` | an order-statistic word (`median`/`quantile`/`iqr`/`mode`) or `zscores` called on a Summary |
| `singular` | `Stats.ols` normal equations have no unique solution |
| `bad_payload` | `Stats.decode` text is not a `Stats.encode` snapshot |

A missing `end` after a `Stats.*` call is not a module error but a
general boru dispatch problem — the word collects the following token
(add `end` or parens).

**Upstream defect (boru main @ `64c5ab2`):** a script that imports
`boru:test` *before* `./stats.aql` sees every Summary-returning word raise
`type_error: … expected Summary, got Summary` (a type-identity collision
between `boru:test`'s record types and this module's `class`). Import the
library first. Details and the minimal repro are in
[`dx-report.md`](../dx-report.md#migration-to-boru-main--64c5ab2-2026-10-01).
