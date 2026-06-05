# language-smtlib

A robust, `Text`-based Haskell library for reading, writing and incrementally
streaming the [SMT-LIB 2](https://smt-lib.org/) format.

## Features

- **Full SMT-LIB 2.6 grammar** — commands, terms, sorts, datatypes
  (`declare-datatype(s)`, `match`, `par`), and solver command responses.
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

- Targets SMT-LIB **2.6** as the baseline. The string-escape rules and
  reserved-word set are isolated in `Language.SMTLIB.Syntax.Constant` and
  `Language.SMTLIB.Internal.Lexical` for easy verification against the 2.7
  reference.
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
