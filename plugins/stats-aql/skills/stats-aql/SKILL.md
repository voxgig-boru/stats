---
name: stats-aql
description: Use when writing or editing boru code that calls the Stats statistics library — Stats.mean / variance / stddev / median / quantile / mode / skewness / kurtosis / covariance / correlation / linreg / normal-pdf / normal-cdf / zscores, the streaming Stats.summary accumulator (push / merge / encode / decode), or the matrix/dataset words (col-means / cov-matrix / cor-matrix / standardize / ols), or any file that does `import "./stats.aql"`. Provides the exact boru calling convention (which is not C/Python/JS), the API with its List-or-Summary and mutation semantics, verified copy-paste idioms, and fixes for the mistakes agents most often make (foreign call syntax like `Stats.mean(xs)`, missing `end` terminators, calling order statistics on a Summary).
---

# Calling the Stats statistics library (boru)

Descriptive, inferential, and matrix statistics. Public surface = the
`Stats` namespace plus the `Summary` type. Everything below is verified
against boru main @ `64c5ab2` (2026-09-30).

## Import

```boru
import "./stats.aql"
```

- A relative path resolves against the **importing file's own
  directory** (not the working directory) — from `test/`, write
  `import "../stats.aql"`.
- No `end` is needed after `import`.
- Import `./stats.aql` **before** `boru:test`: importing `boru:test` first
  trips an upstream type-identity defect on boru main @ `64c5ab2`
  (`type_error: … expected Summary, got Summary`).
- The library imports its own deps (`boru:math-util`, `boru:array-util`,
  `boru:matrix-util`, `boru:struct-util`). But if **you** build a `Matrix`
  to pass to the dataset words, add `import "boru:matrix-util"` yourself —
  the library's import does not re-export the `MatrixUtil` binding.

## The one calling rule

boru has no `f(a, b)` and no `obj.method(a)`. A `Stats` call is written
**forward** — verb first, then the arguments — **terminated with `end`**
(or wrapped in parens). Without a terminator the verb swallows the
following token — wrong result or a dispatch error.

```
Stats.verb arg1 arg2 … receiver end
```

**Receiver-last.** Every word puts its *receiver* (the thing it reads or
mutates) as the **LAST** argument. For the pure words that receiver is
just the data, and it's the only/last arg anyway (`Stats.mean xs end`).
For the streaming accumulator words the receiver is the `Summary`, so the
value(s) come **first** and the `Summary` comes **last**:

```boru
print ((Stats.mean   [1 2 3 4 5] end)) end          # => 3.0
print ((Stats.median [2 4 4 4 5 5 7 9] end)) end     # => 4.5
def s (Stats.summary [1 2 3 4] end)
def a (Stats.summary [1 2 3 4] end)
def b (Stats.summary [5 6 7 8] end)
def _1 (Stats.push 5 s end)          # value first, accumulator s LAST
def _2 (Stats.push-all [6 7] s end)  # list  first, accumulator s LAST
def _3 (Stats.merge b a end)         # fold b into a; a (the receiver) LAST
```

Receiver-last is what makes **piping** work too: because the `Summary`
is the last param it also binds when it flows in from the **left**, so
both of these are correct and identical —

```boru
def s (Stats.summary [1 2 3] end)
def _1 (Stats.push 5 s end)     # forward: value, then receiver
def _2 (s Stats.push 5 end)     # piping:  receiver from the left, value forward
print ((Stats.count s end)) end # => 5
```

The **only** shape that misbinds is *receiver-first-all-forward*. For
`push`/`push-all` (`Stats.push s 5`) boru main refuses it loudly —
`uncalled_function: call to 'stat-push' matched no signature` from the
check that runs before every `boru X`. `Stats.merge a b` (both arguments
are Summaries) still binds **silently**, folding `a` into `b`. Write
value-first (`Stats.push 5 s`) or pipe (`s Stats.push 5`).

(The core words `each`/`fold`, indexing `get`, and the matrix accessors
`MatrixUtil.row`/`col` read their subject from the stack and stay
subject-first: `xs get (i)`, `mat MatrixUtil.col j`.)

## API (exact call shapes)

Every **descriptive** word takes a `List` of numbers **or** a `Summary`.
The **order-statistic** words take a `List` only.

| Call | Returns | Notes |
|------|---------|-------|
| `Stats.summary xs end` | `Summary` | Build a streaming accumulator from a List (`[]` ⇒ empty). |
| `Stats.push x s end` / `Stats.push-all xs s end` | `Summary` | Value(s) first, accumulator `s` **last**. **Mutates** `s`, returns it. |
| `Stats.merge b a end` | `Summary` | Fold moments of `b` into `a` (receiver `a` **last**, mutated & returned). Always compatible. |
| `Stats.encode s end` / `Stats.decode text end` | `String` / `Summary` | jsonic snapshot round-trip; bad text raises `bad_payload`. |
| `Stats.mean x end` / `sum` / `count` / `min` / `max` / `range` | `Float`/`Integer` | `x` = List or Summary. |
| `Stats.variance x end` / `stddev x end` | `Float` | **Sample** (n-1). Needs ≥ 2 values. |
| `Stats.pvariance x end` / `pstddev x end` | `Float` | **Population** (n). |
| `Stats.skewness x end` / `kurtosis x end` | `Float` | Biased g1 / excess g2. |
| `Stats.median xs end` | `Float` | List only. |
| `Stats.quantile xs q end` | `Float` | `q` in `[0,1]`, linear interpolation. List only. |
| `Stats.iqr xs end` / `mode xs end` | `Float` | List only. |
| `Stats.covariance xs ys end` / `pcovariance xs ys end` | `Float` | Sample / population. |
| `Stats.correlation xs ys end` | `Float` | Pearson r. |
| `Stats.linreg xs ys end` | `Map` | `{slope, intercept, r, r2}` (xs predictor, ys response). |
| `Stats.zscores xs end` | `List` | Sample-standardised. |
| `Stats.normal-pdf x {mu, sigma} end` / `normal-cdf x {mu, sigma} end` | `Float` | `sigma > 0`. CDF via an erf approximation (~1e-7). |
| `Stats.col-means mat end` / `col-variances` / `col-stddevs` | `List` | Per-column (rows = observations). |
| `Stats.cov-matrix mat end` / `cor-matrix` / `standardize` | `Matrix` | Sample covariance / correlation / z-scored columns. |
| `Stats.ols x ys end` | `List` | Least-squares coefficients (x = design Matrix; prepend a 1s column for an intercept). |

Catch errors with `do […] error […]`; in the handler read `dot code`
(or `e.code` on a bound error — `get` evaluates its key, so a bare
`get code` is `undefined word: code`). Codes:
`bad_input` (empty/too-few data, q out of range, sigma ≤ 0, length
mismatch), `needs_data` (order statistic or `zscores` called on a Summary),
`singular` (OLS has no unique solution), `bad_payload` (bad decode).

## Idioms (verified)

```boru
import "./stats.aql"
def xs [2 4 4 4 5 5 7 9]
print ((Stats.mean xs end))     end   # => 5.0
print ((Stats.variance xs end)) end   # => 4.571428571428571 (sample)
print ((Stats.median xs end))   end   # => 4.5
```

Streaming accumulator — build once, query many; merge is O(1):

```boru
def s (Stats.summary [] end)
def _1 (Stats.push-all [1 2 3 4] s end)   # value(s) first, accumulator last
def _2 (Stats.push 5 s end)               # or pipe: s Stats.push 5 end
print ((Stats.mean s end)) end            # => 3.0

def a (Stats.summary [1 2 3 4] end)
def b (Stats.summary [5 6 7 8] end)
def m (Stats.merge b a end)               # fold b into a; a is the receiver
print ((Stats.mean m end)) end            # => 4.5
def back (Stats.decode (Stats.encode m end) end)   # persist + reload
```

Dataset (rows = observations, cols = variables):

```boru
import "boru:matrix-util"
def mat (MatrixUtil.create [[1 2] [3 6] [5 10] [7 12]])
print ((Stats.col-means mat end)) end          # => [4.0, 7.5]
def cov (Stats.cov-matrix mat end)             # => Matrix(2x2)
```

## Common mistakes

| ✗ Don't | ✓ Do | Why |
|---------|------|-----|
| `Stats.mean(xs)` / `xs.mean()` | `Stats.mean xs end` | boru has no call/method syntax. |
| `Stats.mean xs` mid-expression, no terminator | `Stats.mean xs end` | The verb swallows the next token. |
| `Stats.push s x` / `Stats.merge a b` (receiver first) | `Stats.push x s` / `Stats.merge b a` (receiver **last**), or pipe `s Stats.push x` | Receiver-last convention: the `Summary` is the last arg. Receiver-first `push`/`push-all` is rejected by the pre-flight check (`uncalled_function`); receiver-first `merge` (two Summaries) binds **silently** and folds `a` into `b`. |
| `Stats.median s end` on a Summary | pass the raw **List** | Order statistics need the data; a Summary raises `needs_data` (inside `do […]`; written directly, the pre-flight check rejects it with a misleading `require-list: return value 1` type_error — an upstream checker false positive). |
| treat `Stats.variance` as population | `Stats.pvariance` for population | Bare `variance`/`stddev` are **sample** (n-1). |
| keep a pre-`push` copy of a Summary | none — `push`/`merge` mutate in place | The argument and the return value are the same object. |
| `e get code` / `lr get slope` | `e.code` / `lr.slope` / `dot code` in a handler | `get` evaluates its key; a bare field name is an `undefined word`. |
| `[Stats.mean Stats.median]` / `myfn Stats.mean xs` (a Stats word passed as data) | `[Stats.mean/v Stats.median/v]` / `myfn Stats.mean/v xs` | A bare name holding a function **calls** (`uncalled_function` / `no_signature` at check); `/v` passes the value. (`xs each Stats.mean` happens to work — `each` takes a bare word as its body — but `/v` is always safe.) |
| `import "boru:test"` before `./stats.aql` | import `./stats.aql` first | Upstream defect on boru main @ `64c5ab2`: `expected Summary, got Summary`. |
| build a Matrix without importing matrix-util | `import "boru:matrix-util"` in your script | The library's deps are not re-exported to callers. |
| `"label" print (v) print` | `print (v)`, one per statement | `print` collects forward (a line break is not a barrier); chains print out of order. |

## By design (not bugs)

- **Receiver-last binds two ways.** `Stats.push value s` (forward) and
  `s Stats.push value` (piping) are identical; only receiver-first
  (`Stats.push s value`) misbinds — loudly for `push`/`push-all` (the
  pre-flight check rejects it), silently for `merge` (two Summaries).
- **Order statistics need a List, never a Summary.**
  `median`/`quantile`/`iqr`/`mode` raise `needs_data` on a `Summary` —
  the raw data is gone once it's folded into running moments. Keep (or
  re-pass) the List for those words.
- **`eq` is identity for Lists/Maps; use `deq` for structure.**
  `[1 2 3] eq [1 2 3]` is `false` (different objects); `[1 2 3] deq
  [1 2 3]` is `true`. Compare Summaries/encoded snapshots with `deq`, and
  never assert list results with `eq`.
- **Want a mutable Map/List? use `flex`.** Plain `{…}`/`[…]` are
  immutable; `flex {a: 1}` gives a Map you can `set` into. `Summary`
  itself is a sealed `class` — construct it only via `Stats.summary` and
  mutate only through `push`/`push-all`/`merge`.
- **Integer overflow is fail-loud (intended).** boru `Integer` is a
  signed 64-bit value (max `9223372036854775807`) and overflow **raises**
  `integer_overflow`, it does not wrap. Stats floats sums-of-squares
  up front (all moment math is `Float`) so large counts don't trip it —
  pass Floats if you're near the edge.
- **Matrix operand-order gotchas** (only if you build matrices yourself):
  the forward form `MatrixUtil.mat-mul X Y` computes **Y·X** (boru's one
  argument-order rule: forward args fill the signature in written order,
  so a non-commutative word reads backwards — for `XᵀX` write
  `MatrixUtil.mat-mul X (MatrixUtil.transpose X)`), and
  `MatrixUtil.elem` is `(col, row)`, not `(row, col)`. Both are silent
  wrong-shape/out-of-bounds, not clean errors. Prefer `MatrixUtil.row` +
  List indexing.

If the full repo is available, `AGENTS.md`, `api.json` (machine-readable
signatures), and `docs/reference.md` have the complete guide;
`test/stats_smoke_test.aql` is a runnable example.
