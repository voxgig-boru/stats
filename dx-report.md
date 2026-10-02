# Developer-experience report: stats on boru

**Date:** 2026-06-25
**boru build under test:** `boru-lang/boru` @ `12a44e0`
(`12a44e0c6ca3f49cd35a871b573fd96bc13d7fd6`, main as of 2026-06-24, PR
#189; built locally with `GOFLAGS=-mod=mod`; `boru -version` reports
`boru 12a44e0-main`).
**Context:** gotchas hit while building this statistics library — a new
module exercising `boru:matrix-util`, `boru:math-util`, the numeric types,
classes, and `do`/`error` against this build. All five suites
(`stats_*`) pass on it across the interpreter, `boru check` (0 errors),
and `boru --compile` (identical to the interpreter), enforced by
`test/divergence/run.sh`.

Severity: **🔴 high** (silent wrong results / crash / blocks a use case) ·
**🟡 medium** (friction, clear workaround) · **🟢 low** (papercut).

> **Current status:** the library and all five suites run green on boru
> main @ `64c5ab2` — see the next section. Everything after it is the
> original 2026-06-25 report and its 2026-07-11 upgrade note, kept as
> history; the table in the next section gives each finding's status on
> main.

---

## Migration to boru main @ 64c5ab2 (2026-10-01)

**boru build under test:** boru-lang/boru main @ `64c5ab2` (2026-09-30;
`boru -version` → `boru 0.1.0-dev (git 64c5ab2f3aed)`), 1,587 commits past
the last verified build (`6185620`, 2026-07-21).

**Result.** All five suites exit 0 and print `all green` under `boru X`
— which on main means they **fully compile** (there is one execution
path now: bytecode on the VM, or `compile_failed`) — and `boru check`
reports **0 errors, 0 warnings** on every suite and on `stats.aql` (one
info each, below). `test/divergence/run.sh` enforces exactly that.

### Breaking changes hit (language drift, migrated idiomatically)

| # | Change on main | What it broke here | Migration |
|---|----------------|--------------------|-----------|
| 1 | `/r` renamed `/v` (ADR-011, 2026-08-19); `ref` → `valof` | the `export "Stats" {…: stat-x/r}` map no longer parsed | `stat-x/v` |
| 2 | Relative imports resolve against the **importing file's** directory (run and check) | every suite's `import "./stats.aql"` | `import "../stats.aql"` in `test/`; docs reworded |
| 3 | One execution path; `--compile` / `--force-compile` / `--no-compile` and `BORU_*COMPILE` retired | `test/divergence/run.sh` compared those modes | harness rewritten: compiled run + check gate |
| 4 | `print` collects a forward argument and **a line break is not a barrier** | each suite's tail `"---" print` / `"fail count: " print …` printed out of order and left `"---"` on the stack for `Assert.equal` (`expected 9, got ---`) | one `print (value)` per statement; `Assert.equal 0 (Test.fail-count)` |
| 5 | `get` evaluates its key (bare field names are words) | docs: `lr get slope`, handler `error [get code]` → `undefined word` | `lr.slope`; handler `error [dot code]` |
| 6 | A bare name holding a function **calls** wherever it appears | nothing in the library (no fn values passed); a caller passing a Stats word as data | docs: `xss each Stats.mean/v` |
| 7 | `Test.check-prop` leaves its PropertyResult map on the stack | `stats_prop_test` ended with five maps printed after `all green` | `end drop` after each call (results are read back via `Test.results`) |
| 8 | Receiver-first `Stats.push s x` / `Stats.push-all s xs` is now **loud** (`uncalled_function`, at check) instead of a silent swap | — (an improvement) | docs updated; `Stats.merge a b` (two Summaries) is still silent |
| 9 | Map/record printing is insertion-ordered | doc outputs of `Stats.encode` / `linreg` showed sorted keys | docs updated to the real output (`{n:5 mean:3.0 m2:…}`) |
| 10 | Float last-ulp: `Stats.correlation [1 2 3 4 5] [2 4 5 4 5]` is `0.7745966692414833` (was `…834`) | doc comments only (tests are tolerance-checked) | docs updated |

No test case, expected value or tolerance was changed or removed. The
verification pass only *added* cases, for D6 and D7 below. (`Assert.equal x y
<=> y x Assert.equal`, and its documented stack order is *actual first,
expected second*. The suite summaries' forward `Assert.equal 0
(Test.fail-count)` therefore labels correctly — `expected 0, got N`. The
older stack-form assertions inside `stats_unit_test`'s `Test.test` bodies
write the expected value first (`3.0 (Stats.mean xs end) Assert.equal`), so
a failure there labels the two the other way round. Equality is symmetric,
so pass/fail is unaffected; those assertions were left as written.)

### Upstream defects worked around (minimal repros)

**D1 🔴 runtime answer bug — a name read inside `do {k: [expr]}` leaks.**
A fn-local name read inside a `do {…}` map value makes a same-named local
(var- *or* def-bound) unresolvable — later in the same `each` body, and
in a **later, unrelated fn**:

```boru
def f fn [[x:Integer] [Map] [ def r (x add 1) do {k: [r]} ]]
def g fn [[xs:List] [List] [ xs each [var [[r] r]] ]]
print (f 1)      # {"k": 2}
print (g [1 2])  # expected [1, 2]; actual: undefined word: r
```

```boru
def f fn [[xs:List] [Map] [ def fs xs do {k: [fs get 0]} ]]
def g fn [[xs:List] [List] [ def fs xs  fs each [var [[x] (x add 1)]] ]]
print (f [1 2])  # {"k": 1}
print (g [1 2])  # expected [2, 3]; actual: undefined word: fs
```

Here it surfaced three ways: `Stats.mode` (`undefined word: v` from its own
`do {…}` state maps), `Stats.ols` after `Stats.linreg` (`linreg`'s
`do {… r: [r] …}` broke `solve-linear`'s pivot fold `[var [[r best] …]]`),
and `Stats.zscores` after `Stats.mode` (`undefined word: fs`). That last
one made one failing `Test.test` block break later, unrelated blocks.
Not in NUR.md (unrecorded). **Workaround:** every `do {k: [expr]}` map in
`stats.aql` (`mode`, `linreg`, `encode`) is now a plain map literal
`{k: (expr)}` — map values auto-evaluate on main, so this is the idiomatic
spelling anyway. Commented in place.

**D2 🟡 compile defect (NUR356 family) — a map literal as an `if` arm.**

```boru
print ({cur: 0} [1 2 3] [var [[v st] if (v gt 1) [{cur: v}] [st] ]] fold)
# [boru/compile_failed]: … fn fold$body: a branch arm leaves a list or map
# literal the interpreter keeps pending past the `if` … (NUR356)
```

**Workaround:** `Stats.mode` binds both candidate states with `def` before
the `if` and the arms only name them (`if (…) [won] [st1]`). Commented in
place; remove when NUR356 is closed.

**D3 🔴 runtime answer bug — `boru:test` breaks a user class's identity.**
Importing `boru:test` before a module that mints a `class` makes that
class's fn **return** check (and `is M.Box` at the importer) fail:

```boru
# m.boru
def Box class {n: 0}
def mk fn [[x:Integer] [Box] [ make Box {n: x} ]]
export "M" {mk: mk/v, Box}

# main.boru
import "boru:test"
import "./m.boru"
print (M.mk 1)   # expected Class/Box{n:1}
                 # actual: type_error: mk: return value 1: expected Box, got Box
```

Swapping the two imports fixes it. The likely cause is a minted-type-ID
collision: the VM's RET check canonicalises the declared type by ID in the
running registry (`core.CanonicalType`), and `boru:test`'s own record types
(`TestCase`, `TestSpec`, …) appear to be minted on a separate counter
(cf. `design/OPEN-WORDS.0.md` §5.2's "known residual"). Here it made
**every** property in both property suites fail on the first generated
input, and every `Summary`-returning case in `stats_unit_spec` fail.
Unrecorded. **Workaround:** each suite imports `../stats.aql` **before**
`boru:test` (commented in place), and the docs tell callers to do the same.
No library-side workaround exists short of dropping the `Summary` return
annotations.

**D4 🟢 checker false positive — a handler-less `do` is typed as its
body.** `def e (do [Stats.variance [5]])` then `e.code` is reported as
`no_signature: cannot call dot … got (Float, Word)` (the check blocks the
run), though at run time `do` returns the Error and `e.code` is
`bad_input`. Minimal form: any fn declared `[Float]` that raises, then
`def e (do [f 0])  print (e.code)`. The unit suite's
`((do […]).code)` reads sit inside `Test.test` bodies and check clean;
the docs use the handler form `error [dot code]`. Unrecorded.

**D5 🟢 checker false positive — a raising guard arm is not treated as
diverging.** A fn whose guard `if` *raises* on a wrong-typed argument and
otherwise returns the argument is modelled by the check as falling through
to its tail, so a statically-known wrong argument reports a false
return-contract `type_error` instead of the `raise`:

```boru
def need-list fn [[x:Any] [List] [
  if (x is Map) [
    def msg `needs a List`
    raise needs_data msg
  ] []
  x
]]
print (need-list {v: 1})
# expected: the run raises [boru/needs_data]: needs a List
# actual:   check (which blocks the run): [error] type_error: need-list:
#           return value 1: expected List, got Map
```

In this library it is `require-list`: a direct top-level `Stats.median s end`
on a Summary is rejected before the run with `type_error: require-list:
return value 1: expected List, got Summary` — and, because `require-list`
lives in the imported module, the caret points at a line number of
`stats.aql` (192) rendered against the *caller's* file. The program would
fail anyway (with `needs_data`), so no valid code is blocked; inside
`do […]` the check downgrades it to info and the run raises `needs_data`
as documented. Unrecorded. No workaround applied (the guard is correct);
the docs note the misleading message.

**D6 🔴 runtime answer bug — a `def` in a nested `if` arm breaks a later
first call (found by the post-migration verification).** None of the
suites saw this, because each first calls the affected words *before*
`Stats.ols`. A caller who runs `Stats.ols` first got, on the first later
call of `covariance` / `correlation` (`undefined word: fx`), `cov-matrix`
/ `cor-matrix` (`undefined word: mat`) or `zscores` (`cannot call sub` —
its `x` misread). Once a word had been called, it kept working. The
trigger was `solve-linear`'s `def msg` in an `if` arm (never taken) inside
its elimination `each` body. A three-fn module reproduces it, but only
across an `import`; the same code in one file is fine:

```boru
# lib.boru
def a fn [[xs:List] [List] [
  xs each [var [[c]
    if (c lt 100) [] [
      def msg `big`
    ]
    0
  ]]
]]
def c fn [[xs:List] [Float] [
  def fx xs
  0.0 xs [var [[i acc] acc add (fx get 0)]] fold
]]
def b fn [[xs:List] [Float] [
  if ((xs size) gte 1) [] [
    def msg `empty`
    raise bad_input msg
  ]
  c xs
]]
export "M" {a: a/v, b: b/v}

# main.boru
import "./lib.boru"
print (M.a [1 2])       # [0, 0]
print (M.b [1.0 2.0])   # expected 2.0; actual: fold: step 0: undefined word: fx
```

Renaming either `msg`, calling `M.b` before `M.a`, or raising without the
`def` all make it go away. It looks like the same family as D1 (a
fn-local `def` in a nested body leaking into a later fn's name
resolution). Unrecorded. **Workaround:** `solve-linear`'s message def is
named `singular-msg` (commented in place). `stats_unit_test` now opens with
a `words-first-used-after-ols` block that first-calls the five words after
`Stats.ols`. Without the workaround it fails, and so do the `bivariate`,
`distributions` and `dataset` blocks after it.

To look for other call-order effects, the verification ran a sweep. For
each of 37 public call shapes plus 9 error-path calls (`do [...] error
[...]` around a raising call), it ran a program that makes that call first
and then calls every other public word, comparing each result with the
word run alone. On the unfixed module the only first calls that broke
later words were `ols` and the singular-`ols` error path (the five words
above). With the workaround, nothing differs.

**D7 🔴 runtime defect — a `!.` dispatch failure escapes `do … error`.**
Inside a fn, `!.` on a non-Map value produced by a native call is not
trapped by the surrounding `do […] error […]`, nor by the caller's. The VM
raises an untrappable error instead of the canonical `signature_error`:
`cannot call dotr` at top level, and `[boru/internal_error]: bytecode:
internal: CALL_NATIVE_POLY no match for dotr` under `Test.test`. At top
level the same read *is* trapped, and `get "n"` is trapped too:

```boru
import "boru:struct-util"
def f fn [[text:String] [Any] [
  def payload (StructUtil.parse text)
  do [ (payload !. n) ] error [ 0 ]
]]
print (f "42")   # expected 0; actual: error: [boru/signature_error]: cannot call `dotr`
```

In this library, `Stats.decode "42"` (or `"nope"`: any jsonic that parses
to a non-Map) escaped as that error instead of the documented
`bad_payload`. Unrecorded. **Workaround:** `stat-decode` checks
`payload is Map` before the field reads and raises `bad_payload` with the
existing "not a Stats.encode snapshot" message, which is the error the
old handler produced. `stats_unit_test`'s `error-codes` block now covers
`"42"` and `"nope"`.

**Info-level check notes (not gating).** `boru check stats.aql` reports
one `redundant_guard` info in `as-summary` ("guard is always true: x is
already List") — imprecise, since the parameter is `(List tor Summary)`;
the guard is kept. Each suite additionally reports the standard
`module_body_executed_in_check` info for the import.

### Status of the original findings on main

| # | Original finding | On main @ `64c5ab2` |
|---|------------------|---------------------|
| 1 | `get`/`set` read a bare variable index as an atom key | **Fixed** — `get` evaluates its key (`xs get i` is `xs[i]`); bare *field names* now need `.field` / `dot` / `/q` |
| 2 | `{k: [expr]}` evaluates only under `do` | Still true (`{k: [v]}` is a one-element List) — but `{k: (expr)}` / `{k: v}` evaluate, and `do {…}` now trips D1: prefer `{k: (expr)}` |
| 3 | `mat-mul X Y` computes Y·X | Unchanged, and now documented as boru's one argument-order rule (forward args fill the signature in written order), not a special case |
| 4 | `MatrixUtil.elem` is `(col, row)` written forward | Unchanged (same rule; `m MatrixUtil.elem 1 0` reads row 0, col 1) |
| 5 | `StructUtil.parse` collapses `42.0` → Integer | Fixed (since 2026-06-25) |
| 6 | checker `Any`→typed dispatch as an error | The union-param shape checks with 0 errors; now an info-level `redundant_guard` (above) |
| 7 | empty `[]` poisons top-level query types | Fixed — `def acc (Stats.summary [] end)` then `Stats.mean acc` checks clean |
| 8 | one-letter uppercase names parse as type variables | Still true (`def M (Stats.summary [1] end)` → `type: body must be a type value or literal`) |
| 9 | `print` forward-collection reverses chains | Still true, and a line break is not a barrier (row 4 above) |

---

## Update (DX-driven boru fixes)

**2026-06-25.** This module was migrated to boru HEAD's new accessor
semantics and verified against a local boru build that carries three
upstream fixes (comp/r frame over-pop, StructUtil.parse float-fidelity,
and a checker `no_signature` fix). `get`/`getr` now *evaluate* their key,
so the literal bare-word field reads this library used — `(as-summary x)
get n`, `params get sigma`/`mu`, the `st`/`acc` map reads in `mode`, and
the linreg-field and error-`code` reads in the suites — moved to the new
dot sugar `recv.field` (with the quoted-atom `get field/q` form reserved
for the receiver-less, value-on-the-stack case); parenthesised computed
indexing such as `xs get (i)` is unchanged and intended. Because the
StructUtil.parse float-fidelity fix makes whole-valued Float moments
round-trip as Float (`8.0`, not `8`), the per-field `convert Float`
coercion that `Stats.decode` carried as the §5 workaround was removed and
the encode/decode round-trip stays green without it. All five `stats_*`
suites are green and `boru check` reports 0 errors on the module and on
each suite; this requires an boru build carrying these fixes — on older
builds the bare-word reads raise `undefined_word` and decode loses Float
type on whole-valued moments.

---

## 1. 🔴 `get`/`set` read a bare word index as an atom key, silently

`get`/`set` on a List or FlexList index, and on a Map/class field, share one
surface: the index/key argument is taken **literally**. A bare *word*
there is treated as an atom (a field name), not evaluated as a variable.
With a literal integer it works; with a variable it silently returns
`None`:

```boru
def s [10.0 20.0 30.0 40.0]
def i 1
s get 1     # => 20.0   (literal index: fine)
s get i     # => None   (variable read as the atom `i`, not its value 1)
s get (i)   # => 20.0   (parenthesise to force evaluation)
```

The damage is that `None` then flows into arithmetic and fails far from
the cause (`no matching signature for sub`, with a `None` receiver). The
fix is uniform: **parenthesise every variable index** — `xs get (i)`,
`arr set (j) (value)`. (Bare *field-name* keys are correct and intended:
`e get code`, `s set mean (m)`, `params get sigma`. The value position of
`set` evaluates a bare variable fine; only the index/key position is
literal.) `bloom.aql` already parenthesised its bit-array indices; this
report documents *why* for the order-statistic and solver code here.

---

## 2. 🔴 a map-literal value `{k: [expr]}` only evaluates under `do`

The bracketed-value form in a map literal is evaluated **only** when the
literal is prefixed with `do`. A bare `{…}` stores the brackets as a
literal List:

```boru
def v 23.0
def a {best: [v]}        #  a.best == [23.0]   (a one-element List!)
def b (do {best: [v]})   #  b.best == 23.0     (evaluated)
```

This bit the `mode` word: a seed state built with a bare `{best: [fs get
0] …}` carried `best` as `[23.0]` instead of `23.0`, so for all-distinct
data (where the fold never enters the `do {…}` update branch) `mode`
returned a List. A property test (`mode-is-a-member`) caught it. Fix:
build every map that uses the `[expr]` value form with `do {…}`. (The
bloom module only ever used `do {…}`, so it never saw this.)

---

## 3. 🟡 `MatrixUtil.mat-mul X Y` computes `Y @ X` (forward args reversed)

The two forward operands of `mat-mul` bind in reverse of the natural
reading order, so `mat-mul A B` is the product **B·A**, not A·B:

```boru
def amat (MatrixUtil.create [[1 2 3] [4 5 6]])   # 2x3
def bmat (MatrixUtil.create [[1 0] [0 1] [1 1]]) # 3x2
MatrixUtil.mat-mul amat bmat   # => Matrix(3x3) — i.e. bmat·amat, not amat·bmat
```

Easy to miss because the spec's own examples are square (2×2), where the
shape can't reveal the order. For `XᵀX` (covariance, OLS normal
equations) this means writing `MatrixUtil.mat-mul X (MatrixUtil.transpose
X)`. A wrong order here is a *silent* wrong-shape result, not an error,
so it only surfaces in a value check — both the covariance matrix and OLS
were initially wrong until pinned down against known answers.

## 4. 🟡 `MatrixUtil.elem` takes `(col, row)`, not `(row, col)`

`(m MatrixUtil.elem 1 0)` reads **column 1, row 0**. This *is* documented
in the module spec, but it inverts the usual `[row][col]` convention and
produced an out-of-bounds error before being spotted. This library reads
matrices a row at a time with `MatrixUtil.row` (naturally indexed) and
indexes into the resulting List, avoiding `elem` entirely.

## 5. 🟡 `StructUtil.parse` collapses whole-valued Floats to Integer

A snapshot field rendered as `42.0` parses back as Integer `42`, and a
sealed `class` field declared `Float` then rejects it
(`make: field "m2": expected Float … got Integer`). `Stats.decode`
coerces every numeric field (`(payload !. m2) convert Float`,
`… convert Integer` for `n`) so the round trip survives the
type collapse. (`bloom.aql` only round-tripped integer bit indices, so it
never hit this; its one Float, `p`, happened to be non-integral.)

---

## 6. 🟡 `boru check` mis-reports `Any`→typed dispatch as a hard error

A query word typed `[x:Any]` that dispatches `x` to a `List`-typed word
draws `no_signature: no matching signature …` — a hard **error**, not a
warning — even though it runs correctly (gradual `Any` should accept
anything). It surfaces inconsistently: the same call is clean when `x`
is provably a `List`, and errors when `x` is provably the *other* arm
(here a `Summary`). The shape that type-checks cleanly in both
directions: give the coercion helper a **union** param and narrow on the
**positive** branch —

```boru
def as-summary fn [
  [x:(List tor Summary)] [Summary] [
    if (x is List) [build-summary x] [x]   # `is List` (not `is Summary`) narrows cleanly
  ]
]
```

`if (x is Summary) [x] [build-summary x]` (negative-branch narrowing)
still errored; flipping to the positive `is List` test fixed it. This is
the same class of `boru check` false-positive the bloom report noted
(export-by-reference hides use sites); checked *through* a suite the
words type-check, which is what the gating `divergence` job asserts.

## 7. 🟢 the empty-list literal `[]` poisons downstream query types

At top level, `def acc (Stats.summary [] end)` then `Stats.mean acc end`
draws the §6 `no_signature` error, while `[1 2 3] Stats.summary` then
`mean` does not — the empty literal `[]` is typed loosely enough that the
checker can't carry it through the union param. It is invisible inside a
`Test.test`/`each` body (those are opaque to the checker), so only
top-level scripts see it. The empty constructor *runs* fine; the smoke
test simply seeds from non-empty data to keep `boru check` at 0 errors.

## 8. 🟢 single uppercase identifiers are parsed as type variables

`def M (MatrixUtil.create …)` fails with `type: body must be a type value
or literal, got Matrix(2x2)` — a one-letter uppercase name is taken as a
type variable. Bind matrices (and any value) to a lowercase name (`def
mat …`). Multi-letter PascalCase (`Summary`, used as a class) is fine.

## 9. 🟢 `print` forward-collection (carried over)

Unchanged from the bloom report: `print` collects a forward argument, so
chained `(a) print (b) print` reverses. Every print in this module uses
the one-value-per-statement idiom `print (value) end`.

---

## Observations

- **`MathUtil.floor`/`ceil` return `Integer` when applied to a Float**
  (`6.3 MathUtil.floor` ⇒ `6`, an Integer), so the result is directly
  usable as a list index — convenient for the quantile interpolation.
- **`boru:matrix-util` has no inverse/solve.** `mat-mul`, `transpose`,
  `det`, `dot`, `scale`, and the accessors are enough for covariance and
  correlation matrices, but OLS needs a linear solve, so this module
  ships a small Gaussian-elimination solver (partial pivoting) over
  `FlexList`s and feeds it `XᵀX` / `Xᵀy` built from the matrix words.
- **The DX feedback loop still shows.** The two 🔴 items here are
  call-convention sharp edges (literal index keys, `do`-gated map values)
  rather than interpreter bugs; both are catchable by property tests, and
  one was caught exactly that way.

---

## Summary

| # | Severity | Issue | Workaround |
|---|----------|-------|------------|
| 1 | 🔴 | `get`/`set` read a bare variable index as an atom key (silent `None`) | parenthesise variable indices: `xs get (i)` |
| 2 | 🔴 | `{k: [expr]}` map value only evaluates under `do` | build such maps with `do {…}` |
| 3 | 🟡 | `mat-mul X Y` is `Y·X` (silent wrong shape) | write `mat-mul X (transpose X)` for `XᵀX` |
| 4 | 🟡 | `MatrixUtil.elem` is `(col, row)` | use `MatrixUtil.row` + List indexing |
| 5 | 🟡 | `StructUtil.parse` collapses `42.0` → Integer | coerce field types on decode |
| 6 | 🟡 | `boru check` flags `Any`→typed dispatch as an error | union param + positive `is List` narrowing |
| 7 | 🟢 | empty `[]` literal poisons top-level query types in `boru check` | seed from non-empty data in checked scripts |
| 8 | 🟢 | one-letter uppercase names parse as type variables | bind values to lowercase names |
| 9 | 🟢 | `print` forward-collection reverses chains | one `print (value) end` per statement |

---

## Upgrade note — `main` @ 0721e8 (2026-07-11)

Re-evaluated against the then-newest `main` (`0721e8280e01`, 17 days past
the pinned `12a44e0`). **The pin stays at `12a44e0`** — `main` has landed
breaking changes that this module has not migrated to, and the fetch/CI
build paths were blocked in that session (details and the Go-module-proxy
workaround are in
[`aql-language-dx-report.md`](aql-language-dx-report.md#update--2026-07-11-re-evaluation-against-newer-main)).
What changes when the pin is eventually bumped:

- **#1 is fixed.** Bare `get` no longer treats a variable as an atom key —
  `xs get i` now evaluates `i`, so the silent-`None` trap is gone. The
  parenthesised `xs get (i)` this module uses keeps working.
- **New: `get` keys must be quoted.** The flip side: a *literal* key must
  be `get k/q` or `get "k"` — bare `get n` now raises `undefined word`.
  Every bare-atom `get` here (`get n`, `st get cur`, `e get code`, …)
  needs quoting, or a dot-access where the receiver is a class (`s.n`).
- **New: matrix types namespaced.** Bare `Matrix` is gone; the portable
  `fn`-param annotation is `Any` (dotted `MatrixUtil.Matrix` isn't valid
  in a param spec). The eight `[mat:Matrix]` / `[x:Matrix …]` signatures
  become `[mat:Any]`.
- **New: `Array` removed** (→ `FlexList`); the OLS solver's `make Array`
  becomes `make FlexList`, and its `convert List` becomes an `each`.
- **New: execution is check-gated and compiles by default.** `boru X` now
  refuses to run if the pre-flight check reports any error (`-no-check`
  escapes), and the default engine is the byte compiler (`-no-compile`
  escapes).

I applied all of the above and the descriptive/order/bivariate/
accumulator/distribution words then run correctly on `0721e8`. But the
**matrix/dataset words hit a wall**: with `[mat:Any]` the checker draws
false `no_signature` errors on them through an import, and the new
check-gate refuses to run them; even with `-no-check` the default
compiler mis-dispatches `iota` in that path. There is no valid matrix
annotation that satisfies the checker (bare `Matrix` gone, dotted names
rejected, aliases don't unify), so the block is **upstream**, not in this
module. The pin therefore stays at `12a44e0` — see
[`aql-language-dx-report.md`](aql-language-dx-report.md#update--2026-07-11-re-evaluation-against-newer-main)
for the full attempt. Revisit once `main` settles behind a tag.

All nine findings above still reproduce on `12a44e0`, where every suite
stays green across the interpreter, `boru check`, and the byte compiler.
