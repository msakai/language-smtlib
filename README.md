# language-smtlib

[![build](https://github.com/msakai/language-smtlib/actions/workflows/build.yaml/badge.svg)](https://github.com/msakai/language-smtlib/actions/workflows/build.yaml)
[![Hackage](https://img.shields.io/hackage/v/language-smtlib.svg)](https://hackage.haskell.org/package/language-smtlib)

A robust, `Text`-based Haskell library for reading, writing and incrementally
streaming the [SMT-LIB 2](https://smt-lib.org/) format.

## Features

- **Full SMT-LIB 2.7 grammar** — commands, terms, sorts, datatypes
  (`declare-datatype(s)`, `match`, `par`), the 2.7 additions (`lambda`,
  `declare-sort-parameter`, `define-const`, the `_` wildcard pattern), and
  solver command responses.
- **`Text`-based** throughout, with rich parse errors from
  [megaparsec](https://hackage.haskell.org/package/megaparsec).
- **Optional source spans.** Every AST node carries a final annotation type
  parameter `a`. Use `()` for a plain tree or `SrcSpan` for one decorated with
  source offsets; `noAnn` (= `void`) erases annotations uniformly.
- **Incremental S-expression framer** with attoparsec-`Partial`-style
  semantics: it distinguishes *complete* / *needs-more-input* / *error* and
  reads only as much as needed to frame one S-expression — so a REPL can prompt
  for continuation lines and a pipe driver never blocks reading past one
  command.
- **Round-trip guarantee.** `parse . render == id` for well-formed trees; the
  printer is the single source of truth for symbol/string quoting.

## Quick start

```haskell
{-# LANGUAGE OverloadedStrings #-}
import qualified Data.Text.IO as T
import Language.SMTLIB

main :: IO ()
main = do
  src <- T.readFile "problem.smt2"
  case parseScript "problem.smt2" src of
    Left err     -> putStr (errorBundlePretty err)
    Right script -> T.putStr (renderScript script)   -- canonical re-print
```

Parse into location-free trees with `parseScript'` / `parseCommand'` /
`parseTerm'`, or keep spans with `parseScript` / `parseCommand` / `parseTerm`.

### Incremental input (REPL)

```haskell
import Language.SMTLIB

-- frameCommand decides the boundary before parsing:
--   Done (Right cmd) rest  -- a command, plus the unconsumed remainder
--   Done (Left err)  rest  -- a complete frame that failed to parse
--   Partial k              -- input ends mid-command: prompt for more, then `feed`
--   Failed fe rest         -- a framing error (EndOfInput = clean end of stream)
step = frameCommand "(assert (> x"   -- => Partial ...
```

### Streaming from a handle or solver pipe

```haskell
import Language.SMTLIB.Reader.Handle

driver h = do
  r <- newHandleReader h
  readCommand r   -- reads only until one command is complete; never over-reads
```

## Modules

| Module | Purpose |
| --- | --- |
| `Language.SMTLIB` | umbrella: AST + parser + printer |
| `Language.SMTLIB.Syntax` | the AST (`Term`, `Command`, `Sort`, …) and annotation machinery |
| `Language.SMTLIB.Parser` | whole-text + incremental parsing |
| `Language.SMTLIB.Parser.SExpr` | the low-level incremental framer |
| `Language.SMTLIB.Parser.Response` | solver-response parsers |
| `Language.SMTLIB.Printer` | rendering to `Text` |
| `Language.SMTLIB.Reader` / `.Reader.Handle` | pure / `Handle`-based incremental readers |

## Conformance notes

- Targets SMT-LIB **2.7** as the baseline. The string-escape rules and
  reserved-word set are isolated in `Language.SMTLIB.Syntax.Constant` and
  `Language.SMTLIB.Internal.Lexical` for easy verification against the 2.7
  reference. The `->` map sort parses as an ordinary sort application; the
  higher-order apply operator `_` is parsed where it coincides with the
  indexed-identifier syntax (`(_ f x)`), matching the 2.7 concrete grammar
  (Appendix B), which adds no dedicated application production.
- As a benign superset, Unicode letters are accepted in simple symbols (so
  identifiers like `あいうえお` need no quoting), and `(push)` / `(pop)` without
  a numeral are read as `(push 1)` / `(pop 1)`.
- Numeric literals (decimal/hex/binary) keep their raw lexeme, so printing
  round-trips byte-for-byte; use the interpreters in
  `Language.SMTLIB.Syntax.Constant` for their values.

## Building

```
stack build
stack test     # round-trip properties, framer units, and sample files
```

### Testing against large external benchmarks

To stress-test the parser and printer against the full SMT-LIB / SMT-COMP
benchmark suites on [Zenodo](https://zenodo.org/), there is an optional
`language-smtlib-conformance` driver, built only behind the `conformance` flag
(so it is never part of the normal build, test suite, or CI) and run on
benchmark data that is downloaded separately and never committed. See
[`conformance/README.md`](conformance/README.md).

### Round-trip checking a corpus of `.smt2` files

For a quick, dependency-free check against an arbitrary collection of `.smt2`
files (for example the example/regression suites shipped with cvc5, OpenSMT,
Yices2, or Z3), use [`scripts/roundtrip-check.sh`](scripts/roundtrip-check.sh).
It drives the `language-smtlib-exe` front end (parse → render) over every file
and verifies that the canonical rendering is idempotent:

```
scripts/roundtrip-check.sh [--build] [--out DIR] [PATH...]
```

For each file it runs the parser/printer twice and compares the results:

- **stage 1** — `parse(src) → out1`; counted as `parse_fail` if the source does
  not parse (this just means the input is not standard SMT-LIB 2.7, e.g. a
  solver-specific extension, a negative-test file, or non-`smt2` data);
- **stage 2** — `parse(out1) → out2`; counted as `reprint_fail` if our own
  output fails to re-parse;
- **compare** — `out1 == out2`; counted as `diff` if the rendering is not
  idempotent.

Because the library contract is `parse . render == id`, a stable canonical
rendering (`out1 == out2`) is a necessary consequence, so any `reprint_fail` or
`diff` flags a genuine parser/printer bug — and the script exits non-zero only
in that case, making it usable as a CI gate. Options:

- `--build` runs `stack build` first;
- `--out DIR` writes the failing-file lists to `DIR` (`parse-fail.tsv` includes
  the first parse-error message for each file);
- `PATH...` are the files and/or directories to scan (directories are searched
  recursively for `*.smt2`; default: the current directory).

```
# example: build, then check the bundled solver corpora, saving failure lists
scripts/roundtrip-check.sh --build --out /tmp/rt misc
```
