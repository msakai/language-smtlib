# Solver extensions and support status

`language-smtlib` targets **SMT-LIB 2.7**. Real solvers extend the format with
their own commands, responses and surface syntax, and those extensions show up
throughout the example/regression suites shipped with cvc5, Z3, Yices2 and
OpenSMT. This document catalogs the extensions that appear in those corpora and
records whether — and how — the library handles each one.

Status legend:

| Status | Meaning |
| --- | --- |
| ✅ **Modeled** | Parsed into a dedicated typed AST node (standard 2.7, plus the benign supersets listed at the end). |
| 🟡 **Lenient** | Parsed but kept **verbatim** — an extension *command* as `UnknownCommand`, an extension *response* as `ROther`. No typed model; the raw s-expressions are preserved so the application can interpret them. Requires the lenient parser (see below). Round-trips through the printer. |
| ❌ **Unsupported** | A parse error. These are non-command extensions to the term/sort/lexical grammar; there is currently no way to accept them. |

The validation behind this table (running the strict parser over the four
solver corpora, then re-running the failures through the lenient parser) is
summarised in [PR #18](https://github.com/msakai/language-smtlib/pull/18).

## Extension commands — 🟡 lenient (`UnknownCommand`)

By default command parsing is **strict**: an unrecognized head keyword is a
parse error. The lenient parsers keep such a command instead:

```haskell
import Language.SMTLIB   -- re-exports pScriptLenient via Language.SMTLIB.Parser

parseWith pScriptLenient "<input>" src
```

`pCommandLenient` / `pScriptLenient` (defined in `Language.SMTLIB.Parser.Command`
and re-exported from `Language.SMTLIB.Parser`, run through `parseWith`) produce

```haskell
UnknownCommand !Symbol [SExpr a]   -- head keyword + raw argument s-expressions
```

for any command whose head keyword is not one of the 32 recognized commands. The
fallback fires **only** on an unknown head keyword: a *recognized* command with
malformed arguments (e.g. `(assert)`) still fails, so genuine syntax errors are
not swallowed. Both `language-smtlib-fmt --lenient` and the whole-text
`parseWith pScriptLenient` entry points expose this behavior.

The extension commands observed in the solver corpora, grouped by feature:

| Feature | Commands | Solver(s) |
| --- | --- | --- |
| Interpolation | `get-interpolant`, `get-interpolants`, `get-interpolant-next`, `get-unsat-model-interpolant`, `get-unsat-core-lemmas` | cvc5, OpenSMT, Yices2 |
| Abduction | `get-abduct`, `get-abduct-next` | cvc5 |
| Synthesis / SyGuS | `declare-var`, `find-synth`, `find-synth-next` | cvc5 |
| Separation logic | `declare-heap` | cvc5 |
| Model exploration | `block-model`, `block-model-values`, `get-model-domain-elements`, `check-sat-assuming-model` | cvc5, Yices2 |
| Quantifier elimination | `get-qe`, `get-qe-disjunct` | cvc5 |
| Datalog / Horn (Z3 μZ / Spacer) | `declare-rel`, `declare-var`, `rule`, `query` | Z3 |
| Codatatypes | `declare-codatatype`, `declare-codatatypes` | cvc5 |
| Quantifier-instantiation pools | `declare-pool` | cvc5 |
| Diagnostics / control | `simplify`, `get-difficulty`, `get-learned-literals`, `get-timeout-core`, `get-timeout-core-assuming` | cvc5 |

The list is illustrative, not exhaustive — the lenient parser accepts **any**
unknown head keyword, so solver commands not seen in these corpora are handled
the same way.

## Extension responses — 🟡 lenient (`ROther`)

Solver-response parsing (`Language.SMTLIB.Parser.Response`, `pCommandResponse`)
is **always** lenient: an unrecognized response is kept as

```haskell
ROther (SExpr a)
```

so a driver reading a solver's stdout never fails on a response shape it does
not model (extension `get-info` fields, solver-specific `(error …)` payloads,
custom `get-value`/model formats, etc.). It also round-trips through the printer.

## Non-command syntactic extensions — ❌ unsupported

These extend the **term / sort / lexical** grammar rather than the command set,
so command-level leniency does not help — they are still parse errors. They are
listed here so the gaps are documented, not hidden. (Note that some
solver-specific *operators* are **not** in this list because they already parse
as ordinary function applications and so need no special handling — e.g. the
separation-logic operators `sep`, `pto`, `emp`, `nil`; only the `declare-heap`
command needs leniency.)

| Extension | Example | Solver | Notes |
| --- | --- | --- | --- |
| Finite-field literals | `#f0m3` (`#f`⟨value⟩`m`⟨modulus⟩) | cvc5 (theory `FF`) | A new numeric literal shape the framer cannot lex. |
| `set.comprehension` binder | `(set.comprehension ((x U)) φ t)` | cvc5 (sets) | A binder form; its `((x U))` binder list is not a term. |
| Character code-point index | `(_ char #x93A83)` | cvc5 (strings) | An indexed identifier whose index is a hex literal, not a numeral/symbol. |
| Nullary application | `(nullable.some)`, `(fp)` | cvc5 | A 0-ary function applied with parentheses; 2.7 requires the bare symbol. |
| Old-style datatype declarations | `(((zero) n) …)` | cvc4-era / TIP benchmarks | Pre-2.6 `declare-datatypes` constructor syntax. |
| C-style string escapes | `"foo \" bar"` | OpenSMT | 2.6+ strings only escape `"` by doubling it (`""`); backslash escapes are not recognized. |
| Reserved word as identifier | `(declare-fun lambda () …)` | cvc5 | `lambda` (and other 2.7 reserved words) cannot name a function. |

Also correctly rejected — and *not* extensions but malformed input — are the
solvers' intentional **negative/error test files** (a recognized command with
bad arguments such as `(get-proof :sat)` or `(get-value ())`, truncated input,
extra parentheses) and files that are not SMT-LIB at all (e.g. `diff` output
mis-named `.smt2`). Leniency deliberately leaves these failing.

## Benign supersets accepted beyond 2.7 — ✅ modeled

For completeness, a few inputs the strict 2.7 grammar forbids are accepted
anyway because they round-trip losslessly; these are documented in the README
"Conformance notes" and are **not** extensions any single solver needs:

- Unicode letters in simple symbols (e.g. `あいうえお`);
- `(push)` / `(pop)` with no numeral, read as `(push 1)` / `(pop 1)`;
- leading-zero numerals (`007`), leading-zero / trailing-dot decimals (`01.5`,
  `1.`), kept verbatim via the raw lexeme;
- non-printable control characters inside string and quoted-symbol literals.

See the README ["Conformance notes"](../README.md#conformance-notes) for the
scope of the library (scripts + solver-response protocol; the theory/logic
*catalog* format is out of scope) and for the well-formedness constraints the
parser does not enforce.
