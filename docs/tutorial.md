# Tutorial: your first statistics session

This is a hands-on lesson. By the end you will have built a small boru
script that summarises a column of numbers, reads its centre and spread,
streams data through a running accumulator, merges two of them, and
finishes with a tiny dataset and a correlation. You need no prior
statistics beyond what "mean" and "standard deviation" mean — just a
working `boru` binary (see
[How-to → Install and run](how-to.md#install-and-run-boru)) and this
repository checked out.

> **AI agents:** for the calling convention and a verified cheat-sheet,
> see [AGENTS.md](../AGENTS.md).

Follow along by typing the script into a file as we grow it. We will
build it up in pieces and run it after each step.

---

## Step 1 — import the module and summarise a List

Create a file `explore.aql` next to `stats.aql` with this content:

```boru
import "./stats.aql"

# Print one value per statement, fully grouped — `print (value) end` —
# and output appears in source order. (Chained `(a) print (b) print`
# pairs print out of order, because print collects a forward argument.)

def data [2 4 4 4 5 5 7 9]
print (`count: ${(Stats.count data end)}`) end
print (`mean:  ${(Stats.mean data end)}`) end
print (`min:   ${(Stats.min data end)}`) end
print (`max:   ${(Stats.max data end)}`) end
```

Every descriptive word is written **verb first**, then the data, then
any extra arguments, ending with `end`: `Stats.mean data end`. That is
the whole calling convention — the verb comes first, no `f(x)` and no
`x.f()`. Run it:

```console
$ boru explore.aql
count: 8
mean:  5.0
min:   2.0
max:   9.0
```

Note the `end` after each call. boru words look ahead for arguments, and
`end` marks where the call stops; forget it and the next token gets
swallowed as an argument. (Inputs may be Integer or Float; results come
back as Float, except `count`, which is an Integer.)

---

## Step 2 — centre and spread

A mean alone doesn't tell you how spread out the data is. Add the
median (the middle value) and the standard deviation (typical distance
from the mean). Append below:

```boru
print (`median: ${(Stats.median data end)}`) end
print (`stddev: ${(Stats.stddev data end)}`) end
print (`iqr:    ${(Stats.iqr data end)}`) end
```

Run the whole file:

```console
$ boru explore.aql
count: 8
mean:  5.0
min:   2.0
max:   9.0
median: 4.5
stddev: 2.138089935299395
iqr:    1.5
```

`stddev` here is the **sample** standard deviation (it divides by
`n - 1`); if your data *is* the whole population, use `Stats.pstddev`
instead. The difference and when it matters is in
[Explanation → Sample vs population](explanation.md#sample-vs-population).
`median` and `iqr` are order statistics — they need the raw values
sorted, so they only accept a List (more on that in a moment).

---

## Step 3 — build a running Summary

So far we handed a whole List to each word, which walks it afresh every
time. When data arrives a piece at a time, or you want one object you
can update and merge, build a `Summary` — a streaming accumulator that
holds running moments and answers any descriptive query in one pass.

Add this to the file:

```boru
def s (Stats.summary [2 4 4 4] end)
def _1 (Stats.push-all [5 5 7 9] s end)
print (`mean: ${(Stats.mean s end)} n: ${(Stats.count s end)}`) end
```

```console
$ boru explore.aql
...
mean: 5.0 n: 8
```

We seeded the Summary with four values, then pushed four more. A
`Summary` is mutated **in place**: `push`/`push-all` update `s` and
return the *same* object, which is why we bind the result to a throwaway
`_1`. The descriptive words (`mean`, `variance`, `stddev`, …) accept a
Summary just as happily as a List.

---

## Step 4 — merge two Summaries

Because a Summary stores moments rather than the raw data, two of them
combine in constant time — no re-reading the inputs. Build two and merge:

```boru
def a (Stats.summary [2 4 4 4] end)
def b (Stats.summary [5 5 7 9] end)
def _m (Stats.merge b a end)
print (`merged mean: ${(Stats.mean a end)} merged stddev: ${(Stats.stddev a end)}`) end
```

```console
$ boru explore.aql
...
merged mean: 5.0 merged stddev: 2.138089935299395
```

Same mean and standard deviation as the single List in Step 2 — the
merge is exact, not an approximation. `merge` folds `b` into `a` and
returns `a` (so `a` is mutated; `b` is untouched). This is the basis for
distributed aggregation: workers each build a Summary, and a coordinator
merges them. Why this works in O(1) and stays numerically stable is in
[Explanation → Why a streaming Summary](explanation.md#why-a-streaming-summary).

---

## Step 5 — a tiny dataset and a correlation

Real questions are usually about how *two* variables move together.
Stats has bivariate words over a pair of Lists, and dataset words over a
whole matrix. Create a second file `relate.aql`:

```boru
import "boru:matrix-util"
import "./stats.aql"

def xs [1 2 3 4 5]
def ys [2 4 5 4 5]
print (`correlation: ${(Stats.correlation xs ys end)}`) end
print (`linreg:      ${(Stats.linreg xs ys end)}`) end

def mat (MatrixUtil.create [[1 2] [3 6] [5 10] [7 12]])
print (`col-means: ${(Stats.col-means mat end)}`) end
```

```console
$ boru relate.aql
correlation: 0.7745966692414833
linreg:      {slope:0.6 intercept:2.2 r:0.7745966692414834 r2:0.6000000000000001}
col-means: [4.0 7.5]
```

`correlation` is Pearson's *r* (between -1 and 1); `linreg` fits a
straight line and reports its `slope`, `intercept`, and goodness-of-fit
(`r`, `r2`). The dataset words like `col-means` take a `MatrixUtil`
Matrix whose **rows are observations** and **columns are variables** —
so you must `import "boru:matrix-util"` yourself in scripts that build a
Matrix (the library does not re-export it).

---

## What you've learned

- Descriptive words (`mean`, `median`, `stddev`, …) are written verb
  first, then the data: `Stats.mean data end`.
- The unqualified `variance`/`stddev` are **sample** statistics;
  `pvariance`/`pstddev` are **population**.
- A `Summary` is a streaming, mergeable accumulator built with
  `Stats.summary`; `push`/`merge` mutate it in place.
- Order statistics (`median`, `quantile`, `iqr`, `mode`) need a List.
- Bivariate (`correlation`, `linreg`) and dataset (`col-means`, …) words
  let you relate variables.

## Where to go next

- Solve specific problems with the [How-to guides](how-to.md) — sample
  vs population, streaming, persistence, regression, running the tests.
- Look up exact signatures in the [Reference](reference.md).
- Understand the machinery in the [Explanation](explanation.md).
