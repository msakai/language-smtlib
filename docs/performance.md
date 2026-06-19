# Parser performance

Notes on where the cost is, what has been optimized, and which levers remain.
This is the canonical record referenced from `CLAUDE.md`.

## Where the cost is

Profiling a 37 MB script (≈800k commands, mostly `assert`/`declare-fun`) showed
the work concentrated almost entirely in the parser: parsing is ~94% of time and
~95% of allocation, while the `prettyprinter` side is only ~5%. **Performance
work should target the parser, not the printer.**

## Profiling builds

`-fprof-auto` (automatic per-cost-centre profiling) is gated behind the manual
`profiling` cabal flag, which is **off by default** so that downstream packages
profiling their own code are not cluttered with cost centres from this library
(see the flag description in `package.yaml`).

Build with profiling enabled, then run the round-trip executable to get a report:

```
stack build --flag language-smtlib:profiling --library-profiling --executable-profiling
stack exec --profile -- language-smtlib-exe FILE.smt2 +RTS -p -s
```

`language-smtlib-exe` (`app/Main.hs`) parses a file/stdin and re-emits it
canonically, so it exercises both the parser and the printer on real input.

## What has been done — PR #6 (`perf-parser`, merged 2026-06-07)

All four changes are behaviour-preserving and were verified by the
`parse . render == id` round-trip property suite. They follow the
**dispatch-on-head-token** pattern (read the keyword / first char once, then
`case`) rather than `choice`/`try` cascades — preserve that pattern when adding
commands or term forms.

- **`isSimpleSymbolChar`** (`Internal/Lexical.hs`): replaced an `elem` scan over a
  17-char `String` with direct ASCII range checks, consulting `isAlpha` only for
  non-ASCII code points. This predicate was 5.8% of parse time; it drops off the
  profile entirely.
- **`readInteger`** (`Parser/Internal.hs`): parses straight from `Text` via
  `Data.Text.Read.decimal` instead of `read . T.unpack`, removing a `String`
  allocation per numeral.
- **`pCommand`** (`Parser/Command.hs`): reads the command keyword once and
  dispatches on it, instead of a `choice` of ~30 `tok` alternatives that
  re-scanned and backtracked the keyword for every command (`assert` was the 18th
  alternative). `tok` fell from 3.7% to 2.4% of time.
- **`pTerm` / `parenCompound`** (`Parser/Term.hs`): peeks the first character
  (and, inside a paren, the head word) and dispatches directly, instead of
  `try (qualident)` per term plus a binder cascade. Since term nodes vastly
  outnumber commands, this was the single biggest win.

Measured effect on the 37 MB benchmark (baseline → after each stage):

| Stage | Wall time | Heap allocation |
| --- | --- | --- |
| Baseline | 104.9 s | 343 GB |
| + lexical & command dispatch | 93.5 s (−10.9%) | 308 GB (−10.2%) |
| + term dispatch (cumulative) | 75.2 s (−28%) | 252 GB (−26%) |

Profiled parse time alone fell 28.3 s → 19.4 s (−32%) over the same range.

## Findings and remaining (deferred) levers

- **RTS nursery tuning (`-A64m`) does not help wall time.** GC was never the
  bottleneck: the Gen0 collection count drops dramatically (82,911 → 541) but
  elapsed time is flat. The cost is in the mutator (the parser itself).
- The remaining cost is now **megaparsec's own combinator machinery**
  (`<|>` / `<$` / `takeWhile_` / `hidden` / `getParserState`). This is the
  practical floor without switching parser libraries.
- **Deferred levers** (not done — higher risk, lower expected return):
  - A **span-free fast path** to avoid `withSpan` (`Parser/Internal.hs`), which
    accounts for ~7.6% of time and allocation: every node calls `getOffset`
    twice and allocates a `SrcSpan`. A path that builds `()`-annotated trees
    directly would skip this.
  - **Streaming the CLI** via the existing `frameCommand`, to bound residency.
    Parse-then-render holds the whole AST (~4.5 GB on this benchmark); streaming
    would cut memory but not wall time.
