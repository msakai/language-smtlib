# Changelog for `language-smtlib`

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to the
[Haskell Package Versioning Policy](https://pvp.haskell.org/).

## Unreleased

### Added
- Initial release of the `Text`-based SMT-LIB 2 library.
- Full SMT-LIB 2.6 AST (`Language.SMTLIB.Syntax`) with an optional source-span
  annotation parameter on every node, including datatypes, `match` and `par`.
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

## 0.1.0.0 - YYYY-MM-DD
