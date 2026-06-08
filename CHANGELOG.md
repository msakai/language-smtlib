# Changelog for `language-smtlib`

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to the
[Haskell Package Versioning Policy](https://pvp.haskell.org/).

## Unreleased

- Derive `Ord`, `Generic` and `Hashable` for every AST type (and `SrcSpan`),
  so syntax trees can be used as `Data.Map`/`Data.HashMap` keys.  These
  comparisons and hashes are structural and follow the existing `Eq`
  (numeric literals compare by raw lexeme; annotations participate, so erase
  them with `noAnn` for annotation-insensitive keys).

## 0.1.0.0 - 2026-06-08

- Initial release of the `Text`-based SMT-LIB 2 library.
- Full SMT-LIB 2.7 AST (`Language.SMTLIB.Syntax`) with an optional source-span
  annotation parameter on every node, including datatypes, `match` and `par`.
- SMT-LIB 2.7 syntax additions over 2.6: the `lambda` binder, the
  `declare-sort-parameter` and `define-const` commands, and the `_` wildcard in
  `match` patterns. (The `->` map sort and term-level apply operator `_` already
  fit the existing sort/identifier grammar.)
- SMT-LIB 2.7 reference sample scripts under `test/samples/smt/` (Figures 3.11
  and 3.12, plus the `lambda`/`define-const`, `declare-sort-parameter`, and
  polymorphic list `match` examples).
- megaparsec-based parser (`Language.SMTLIB.Parser`) with whole-text and
  location-free (`parseScript'`/`parseCommand'`/`parseTerm'`) entry points.
- Incremental S-expression framer (`Language.SMTLIB.Parser.SExpr`) with
  `Done`/`Partial`/`Failed` results and minimal reads, plus pure
  (`Language.SMTLIB.Reader`) and `Handle`-based
  (`Language.SMTLIB.Reader.Handle`) incremental readers.
- `prettyprinter`-based printer (`Language.SMTLIB.Printer`) with centralised
  symbol/string quoting and a `parse . render == id` guarantee.
- Solver command-response types and parsers (`Language.SMTLIB.*.Response`).
- Test suite: round-trip properties for every AST type, framer unit tests,
  framer-vs-parser equivalence, and parse/render idempotence over sample files.
