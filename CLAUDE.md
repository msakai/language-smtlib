# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`language-smtlib` is a `Text`-based Haskell library for parsing, printing, and incrementally streaming the **SMT-LIB 2.7** format. It exists to replace the dead `Smtlib` String/Parsec fork that `toysolver` currently vendors (the `toysolver/` subdirectory is a checkout of that consumer, kept for reference; it is not part of this package's build).

## Commands

Built with **Stack** (Haskell). `package.yaml` is the source of truth — `language-smtlib.cabal` is generated from it by hpack on `stack build`. **Do not hand-edit the `.cabal` file**; edit `package.yaml` and rebuild.

```
stack build
stack test                         # round-trip properties + framer units + sample files
stack haddock --no-haddock-deps    # docs; CI keeps this warning-clean
```

Run a single / filtered test (tasty `--pattern`, matches the test-tree path):

```
stack test --test-arguments='--pattern "round-trip"'
stack test --test-arguments='--pattern "framer"'
```

Test against a specific GHC: each supported series has its own snapshot file (`stack-ghc-9.6.yaml`, `-9.8`, `-9.10`, `-9.12`). CI runs all four.

```
stack --stack-yaml stack-ghc-9.12.yaml test
```

Profiling: `-fprof-auto` (automatic cost centres) is gated behind the manual `profiling` flag — off by default so it does not pollute the profiles of downstream packages. Enable it alongside profiling builds:

```
stack build --flag language-smtlib:tools --flag language-smtlib:profiling --library-profiling --executable-profiling
stack exec --profile -- language-smtlib-fmt FILE.smt2 +RTS -p -s
```

Both executables are developer tools gated behind the manual `tools` flag (`stack build --flag language-smtlib:tools`), so they are off by default and out of a plain `stack build`/`stack test` (CI passes the flag explicitly). `language-smtlib-fmt` (`app/Main.hs`) parses a file/stdin and re-emits it canonically — handy for eyeballing round-trip output. The `language-smtlib-conformance` driver round-trips large external benchmark suites and is never run in the normal build/test/CI; see `conformance/README.md` and `scripts/`.

## Architecture

### Two-layer parsing (the central design)

Parsing is deliberately split so that "needs more input" is never confused with a syntax error:

1. **`Parser/SExpr.hs`** — a hand-written, incremental S-expression *framer*. It tracks paren depth, strings, `|...|` quoted symbols, and `;` comments, and returns `Done a rest | Partial k | Failed err rest`. It reads only as much as needed to frame one S-expression (so a pipe driver never over-reads, and a REPL can prompt for continuation via `Partial`/`feed`). `EndOfInput` from a clean end is the benign stream terminator.
2. **`Parser/*` (megaparsec over `Text`)** — runs only on a *complete* frame, so it is responsible purely for syntax errors and produces megaparsec's rich `ParseErrorBundle`.

The framer owns the complete/incomplete/error trichotomy; megaparsec owns error quality. `Parser.hs` exposes both whole-text (`parseScript`/`parseCommand`/`parseTerm`) and incremental (`frameCommand`) entry points. `Reader/` and `Reader/Handle.hs` build streaming readers on top of the framer.

### Parametric annotation AST (`Syntax/`)

Every AST node's **last constructor field is an annotation `a`**, and every type derives `Functor`/`Foldable`/`Traversable` over it. Use `()` for a plain tree or `SrcSpan` (0-based offsets, `Syntax/Annotation.hs`) for a located one; `noAnn` (= `void`) erases annotations uniformly. Parsers capture spans with `withSpan` (`Parser/Internal.hs`), which wraps a parser yielding a constructor still awaiting its final `SrcSpan` field. Public parsers come in span (`parseScript`) and span-free (`parseScript'`, via `noAnn`) variants. The `Syntax/*` modules map one-to-one onto SMT-LIB grammar nonterminals (Constant, Identifier, Sort, Term, Datatype, Attribute, Command, Response). **Scope:** this covers scripts plus the solver-response protocol; the theory/logic *catalog* format (`(theory …)`/`(logic …)` and their attribute grammars) is intentionally not modeled (see README "Conformance notes").

### Printer is the source of truth for quoting

`Printer/Class.hs` (the `Pretty` class) centralises all symbol/keyword/string quoting and escaping, and `Printer.hs` renders to `Text` via `prettyprinter`. The invariant **`parse . render == id`** for well-formed trees is the main correctness guarantee, exercised by the QuickCheck round-trip properties in `test/`.

### Shared lexical conventions (`Internal/Lexical.hs`)

The reserved-word set, simple-symbol character classes, and string-escape rules live here as the *single source of truth* shared by both parser and printer — change them here so the two sides cannot drift. Note: numeric literals (decimal/hex/binary) keep their **raw lexeme** in the AST so printing round-trips byte-for-byte; use the interpreter functions in `Syntax/Constant.hs` to get their values.

## Conventions and gotchas

- **Round-trip is the contract.** When changing the parser or printer, the generated round-trip property suite (`test/Arbitrary.hs` + `test/Spec.hs`) is what guards correctness — its generators deliberately produce symbols/strings that force quoting/escaping.
- **2.7 with documented benign supersets**: Unicode letters are allowed in simple symbols, `(push)`/`(pop)` without a numeral default to `1`, and the parser also accepts (but the grammar forbids) leading-zero numerals/decimals, trailing-dot decimals like `1.`, and control chars in string/quoted-symbol literals — all round-trip-safe. The `n+1` count linkage in `declare-datatypes`/`define-funs-rec` is a well-formedness constraint the parser does not enforce. Keep such deviations documented (see README "Conformance notes").
- **Parser performance**: parsing dominates cost (the printer is ~5%). The parser uses *dispatch-on-head-token* (read the keyword/first char once, then `case`) rather than `choice`/`try` cascades — preserve that pattern when adding commands or term forms. See [docs/performance.md](docs/performance.md) for profiling details, the PR #6 wins, and the remaining (deferred) optimization levers.
