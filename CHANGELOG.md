# Changelog for `language-smtlib`

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to the
[Haskell Package Versioning Policy](https://pvp.haskell.org/).

## Unreleased

- Add `UnknownCommand` (to `Command`) and `ROther` (to `CommandResponse`) so a
  syntactically well-formed but unrecognized command or solver response can be
  kept verbatim for the application to handle, instead of failing the parse.
  Command parsing stays strict by default (`parseScript`/`pCommand` reject an
  unknown head keyword); the new lenient parsers `pCommandLenient` /
  `pScriptLenient` (in `Language.SMTLIB.Parser.Command`, run via `parseWith`)
  produce `UnknownCommand` instead.  The fallback fires only on an unknown head
  keyword — a recognized command with malformed arguments still fails.
  Solver-response parsing (`pCommandResponse`) is always lenient, keeping an
  unrecognized response as `ROther`.
- `language-smtlib-fmt` gains a `--lenient` flag that formats scripts
  containing unrecognized commands (via `pScriptLenient`) instead of failing;
  without it the formatter stays strict as before.
- Derive `Ord`, `Generic` and `Hashable` for every AST type (and `SrcSpan`),
  so syntax trees can be used as `Data.Map`/`Data.HashMap` keys.  These
  comparisons and hashes are structural and follow the existing `Eq`
  (numeric literals compare by raw lexeme; annotations participate, so erase
  them with `noAnn` for annotation-insensitive keys).
- Read the `test/samples/smt/` sample files as UTF-8 explicitly, so the test
  suite no longer fails on the non-ASCII samples under a non-UTF-8 locale
  (e.g. `C`/`POSIX`).
- `Language.SMTLIB.Parser` now re-exports the `Language.SMTLIB.Parser.Command`
  and `Language.SMTLIB.Parser.Response` combinators, making it the single,
  complete public parsing API.  The command combinators (including the lenient
  `pCommandLenient` / `pScriptLenient` variants) are therefore now reachable
  from the umbrella `Language.SMTLIB` module too, matching the response
  combinators and removing the need to import `Language.SMTLIB.Parser.Command`
  separately.  The umbrella drops its own direct `Language.SMTLIB.Parser.Response`
  re-export, as it now arrives transitively through `Language.SMTLIB.Parser`.

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
