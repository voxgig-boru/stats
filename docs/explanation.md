# Explanation

Understanding-oriented discussion of how this statistics library works
and why it is built the way it is. Read this when you want the *why*;
for the *what*, see the [Reference](reference.md), and for *how to get a
job done*, the [How-to guides](how-to.md).

---

## What the library is for

`Stats` covers the everyday statistics of a numeric dataset:
**descriptive** summaries (centre, spread, shape), **order** statistics
(median, quantiles, mode), **inferential/bivariate** measures
(covariance, correlation, regression), simple **distribution** functions
(the normal PDF/CDF and z-scores), and **matrix/dataset** operations
over many variables at once (per-column statistics, covariance and
correlation matrices, standardisation, and ordinary least squares).

There are two ways in, and the design leans on both:

- **Pure functions over a List** — `Stats.mean [1 2 3] end`. Convenient
  for data you already hold in memory; each call walks the List.
- **A streaming `Summary` accumulator** — `Stats.summary xs end`, then
  `push`/`push-all`/`merge`. For data that arrives incrementally, that
  is too large to keep, or that you want to aggregate in parallel.

This is the right tool for batch and streaming summaries of moderate-
dimensional numeric data. It is not a linear-algebra package or a
modelling framework: the matrix words cover the common dataset
operations, but anything past OLS belongs elsewhere.

---

## Why a streaming Summary

A naive `mean` then `variance` then `skewness` over a List walks the
data three times and, for variance, is tempting to compute as
`Σx² - (Σx)²/n` — which loses precision catastrophically when the values
are large and close together (you subtract two big nearly-equal sums).

The `Summary` avoids both problems. It holds the count, the running
mean, and the **central-moment sums** `m2`, `m3`, `m4` (`Σ(x-mean)^k`),
plus the running min/max, and updates them with the **Welford/Pébay**
one-pass recurrences. Each new observation adjusts the moments using the
old mean and the deviation of the new point, so:

- **One pass.** Every descriptive statistic (mean, variance, stddev,
  skewness, kurtosis) is read straight off the stored moments — no
  re-walking the data.
- **Numerically stable.** Deviations are taken from the current mean
  rather than squaring raw values, so there is no catastrophic
  cancellation.
- **O(1) mergeable.** Two Summaries combine with the parallel (Pébay)
  combine formulas, which express the moments of the union purely in
  terms of the two sub-summaries' counts, means, and moment sums — and
  the delta between their means. No raw data is needed, so `merge` is
  constant-time and **exact** (not an approximation). This is what makes
  distributed aggregation cheap: each worker keeps a Summary, and a
  coordinator merges them.

Because a Summary stores only moments, it cannot answer the
order-statistic words — there is no way to recover the sorted data from
`{n, mean, m2, m3, m4, min, max}`. Those words therefore require a List
and raise `needs_data` on a Summary. The same snapshot is exactly what
`encode`/`decode` serialise, which is why a decoded Summary is also
"order-statistic blind".

All the moment arithmetic is done in Float on purpose: boru Integer
overflow is a *hard error*, not a silent wraparound, so sums of squares
are floated up front to keep large datasets from blowing up.

---

## Sample vs population

Variance comes in two flavours that differ only in the divisor:

```
population variance = m2 / n          (Stats.pvariance / pstddev)
sample variance     = m2 / (n - 1)    (Stats.variance  / stddev)
```

Dividing by `n` is correct when your data **is** the whole population.
But when the data is a *sample* drawn from a larger population, dividing
by `n` systematically **underestimates** the true variance, because the
deviations are measured from the sample mean — which is itself pulled
toward the data — rather than the unknown true mean. Dividing by `n - 1`
(**Bessel's correction**) removes that bias. The sample form is the
right default for inference, which is why the unqualified
`variance`/`stddev`/`covariance` are the sample versions and the
population versions carry the explicit `p` prefix.

The same logic governs `covariance` (sample, `n - 1`) vs `pcovariance`
(population, `n`). `correlation`, being a ratio of covariance to the
product of standard deviations, has the `n`/`n-1` factor cancel, so it
needs no sample/population distinction.

---

## Dataset words as matrix algebra

The dataset words treat a Matrix as a data table: each **row** is one
observation, each **column** one variable. That layout lets the
per-variable statistics fall out of matrix algebra.

Center each column by subtracting its mean, giving the centered matrix
`Xc`. Then the **sample covariance matrix** is

```
Cov = (1 / (n - 1)) · Xcᵀ Xc
```

— the `(i, j)` entry is `Σ(x_i - mean_i)(x_j - mean_j) / (n - 1)`,
exactly the sample covariance of columns `i` and `j`, with the diagonal
holding the per-column variances. `cov-matrix` computes precisely this
(it builds `Xc`, forms the Gram matrix `Xcᵀ Xc` via the matrix-util
multiply, and scales by `1/(n-1)`). `cor-matrix` then divides each entry
by the product of the two columns' standard deviations (the square roots
of the diagonal), normalising covariances to correlations in `[-1, 1]`.
`standardize` z-scores each column independently.

---

## How OLS works

`Stats.ols` fits the least-squares coefficients `b` that minimise
`‖y - Xb‖²` for a design matrix `X` (rows = observations, columns =
predictors) and response `y`. The minimiser satisfies the **normal
equations**:

```
(Xᵀ X) b = Xᵀ y
```

So OLS forms the small `k × k` matrix `XᵀX` and the length-`k` vector
`Xᵀy` (where `k` is the number of predictors), then solves that square
system for `b`. There is no intercept term unless you ask for one:
**prepend a column of 1s to `X`** and the corresponding coefficient is
the intercept.

The solve is **Gaussian elimination with partial pivoting**, written
directly in `stats.aql`. This is deliberate: `boru:matrix-util` offers a
matrix multiply and transpose but **no matrix inverse**, so the library
cannot lean on `b = (XᵀX)⁻¹ Xᵀy`. Solving the system by elimination is
both more direct and numerically better than forming an explicit
inverse anyway. The elimination copies the rows into mutable FlexLists,
pivots on the largest-magnitude entry in each column for stability, and
back-substitutes. If a pivot is effectively zero — meaning the predictors
are linearly dependent (a duplicated or constant column, or fewer
independent observations than predictors) — the system has no unique
solution and the word raises `singular` rather than returning garbage.

---

## The normal CDF and its erf approximation

`normal-pdf` is a closed form, but the normal **CDF** has no elementary
antiderivative — it is `0.5 · (1 + erf(z / √2))`, and `erf` itself must
be approximated. The library uses the **Abramowitz & Stegun 7.1.26**
rational-polynomial approximation of `erf`, which has a maximum absolute
error of about **1.5 × 10⁻⁷**. That is far tighter than typical input
precision and costs only a handful of multiplies, so `normal-cdf` stays
a cheap, allocation-free call. The approximation is symmetric (it
mirrors around zero via the sign of the argument), so both tails are
handled by the same polynomial. If you need more than ~7 digits of CDF
accuracy, this is the wrong tool; for the usual probability and
hypothesis-test work it is comfortably exact.

---

## The List-or-Summary polymorphism

Every descriptive word accepts **either** a List **or** a Summary. This
is not two code paths bolted together: internally each word coerces its
argument to a Summary (a List is folded into a fresh one; a Summary is
used as-is) and then reads the answer off the moments. So
`Stats.mean [1 2 3] end` and `Stats.mean (Stats.summary [1 2 3] end) end`
run the *same* computation — the List form just builds a throwaway
Summary first.

This keeps the surface small and consistent: you learn one set of
descriptive verbs and use them whether your data is a literal List or a
long-lived accumulator. The boundary is the order-statistic and
bivariate words, which genuinely need the raw values (you cannot sort or
pair moments), and so are List-only and reject a Summary with
`needs_data` — a deliberate, explicit failure rather than a silently
wrong answer.

---

## Raising errors

Failures raise coded errors with `raise`: `bad_input` for empty or
too-small data, an out-of-range quantile, a non-positive sigma, or
mismatched vector lengths; `needs_data` when an order-statistic word
(or `zscores`) is handed a Summary; `singular` when the OLS normal
equations have no unique solution; `bad_payload` when `decode` is given
text that is not an `encode` snapshot. Handlers catch them with
`do […] error […]` and read `code`/`message` (plus any payload fields)
off the Error value. Coded errors let callers branch on *what* went
wrong (with `case` on the code) rather than scraping a message string.

Two defensive spellings in `stats.aql` are worth noting if you read the
source: a raise *message* is bound with `def` before the `raise`, and
guard `if`s used as statements carry an explicit empty else `[]`. Both
sidestep runtime sharp edges documented in
[`dx-report.md`](../dx-report.md) and are correct on every build.

---

## Further reading

- [Tutorial](tutorial.md) — summarise your first dataset step by step.
- [How-to guides](how-to.md) — task-focused recipes.
- [Reference](reference.md) — the exact API.
