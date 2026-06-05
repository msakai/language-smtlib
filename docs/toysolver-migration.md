# Migrating `toysolver` onto `language-smtlib`

Status: **deferred / future work.** The core `language-smtlib` library is
complete and tested; this note records what is needed to switch
[`toysolver`](https://github.com/msakai/toysolver) off its bundled, heavily
modified `Smtlib` fork and onto this library. Nothing here has been implemented
yet.

## Why

`toysolver` currently depends on a String-based, Parsec-based fork of the
Hackage `Smtlib` package, vendored as a git submodule under
`toysolver/Smtlib/`. Upstream is dead and the fork is hard to maintain. This
library is the `Text`-based, megaparsec/prettyprinter replacement.

## Where the old library is used in toysolver

Grounded in the current toysolver tree:

| File | Imports | Uses |
| --- | --- | --- |
| `app/toysmt/toysmt.hs` | `Smtlib.Parsers.CommandsParsers` | `parseFromFile (parseSource <* eof)` (line ~90); REPL `parse (spaces >> parseCommand <* eof)` and `parse (spaces >> parseCommand)` (lines ~114, ~128) |
| `app/toysmt/ToySolver/SMT/SMTLIB2Solver.hs` | `Smtlib.Syntax.Syntax`, `Smtlib.Syntax.ShowSL`, qualified `Smtlib.Parsers.CommandsParsers` | the whole AST (`Command`/`Term`/`Sort`/…), `showSL` (in `SMT.Error` strings and `printResponse`), `CommandsParsers.parseCommand` in `runCommandString`, builds `CmdResponse`/`AttrValueSymbol` values |
| `test/Test/Smtlib.hs`, `Smtlib/tests/TestSuite.hs` | the fork | round-trip QuickCheck props (already ported into this repo's `test/`) |

Key internal functions in `SMTLIB2Solver.hs` that touch the AST:
`interpretSort`, `interpretFun` (`Term -> SMT.Expr`), `valueToTerm` /
`exprToTerm` (`SMT.Value`/`SMT.Expr -> Term`), `runCommand :: Solver -> Command
-> IO CmdResponse`, `runCommandString`, `printResponse`.

## API mapping (old fork → `language-smtlib`)

| Old | New |
| --- | --- |
| `parseSource :: Parser [Command]` | `parseScript :: FilePath -> Text -> Either MPError (Script SrcSpan)` (or `parseScript'` for `Script ()`) |
| REPL `parseCommand` (whole) | `parseCommand` / `parseCommand'`; for true incremental/pipe input use `frameCommand` or `Language.SMTLIB.Reader.Handle` |
| `showSL :: ShowSL a => a -> String` | `renderText :: Pretty a => a -> Text`; whole script `renderScript`. For a `String`: `T.unpack . renderText` |
| `Smtlib.Parsers.ResponseParsers` | `Language.SMTLIB.Parser.Response` combinators run via `parseWith` |
| Parsec `ParseError` | megaparsec `MPError` (= `ParseErrorBundle Text Void`); render with `errorBundlePretty` / `prettyParseError` |

### String ↔ Text boundary

The old code builds `SMT.Error` messages as `String` via `showSL`, and
`toysolver` interns symbols (`InternedText`). Suggested bridge while migrating:

```haskell
showSLString :: Pretty a => a -> String
showSLString = T.unpack . renderText
```

Symbols are now `Text` (`type Symbol = Data.Text.Text`), so they can be interned
directly without `pack`/`unpack` round-trips.

## AST constructor mapping

Every new node has a trailing annotation field `a`; use the `()`-annotated tree
(`parseScript'` / `noAnn`) unless source spans are wanted. Old fields were
`String`; new ones are `Text`.

| Old (`Smtlib.Syntax.Syntax`) | New (`Language.SMTLIB.Syntax`) |
| --- | --- |
| `type Source = [Command]` | `type Script a = [Command a]` |
| `Term`: `TermSpecConstant`, `TermQualIdentifier`, `TermQualIdentifierT`, `TermLet`, `TermForall`, `TermExists`, `TermAnnot` | `Term`: `TConstant`, `TQualIdent`, `TApp`, `TLet`, `TForall`, `TExists`, `TAnnot`, **plus new `TMatch`** |
| `QualIdentifier`: `QIdentifier`, `QIdentifierAs` | same names |
| `Identifier`: `ISymbol s`, `I_Symbol s [Index]` | unified `Identifier !Symbol [Index a] a` (empty index list = simple symbol) |
| `Index`: `IndexNumeral Int`, `IndexSymbol String` | `IxNumeral !Integer a`, `IxSymbol !Symbol a` |
| `Sort`: `SortId`, `SortIdentifiers` | `Sort (Identifier a) [Sort a] a` |
| `SpecConstant`: `SpecConstantNumeral Integer`, `…Decimal String`, `…Hexadecimal String`, `…Binary String`, `…String String` | `SCNumeral !Integer a`, `SCDecimal !Text a`, `SCHexadecimal !Text a`, `SCBinary !Text a`, `SCString !Text a` (numeric literals keep the **raw lexeme**; hex/bin store digits only) |
| `VarBinding (VB s t)`, `SortedVar (SV s srt)` | `VarBinding !Symbol (Term a) a`, `SortedVar !Symbol (Sort a) a` |
| `FunDec` | `FunctionDec`; `define-fun`/`-rec` now carry a `FunctionDef` |
| `Attribute`, `AttrValue` (`AttrValueConstant`/`AttrValueSymbol`/`AttrValueSexpr`) | `Attribute`/`AttributeWith`, `AttributeValue` (`AVConstant`/`AVSymbol`/`AVSExpr`) |
| `Sexpr`: `SexprSpecConstant`, `SexprSymbol`, `SexprKeyword`, `SexprSxp` | `SExpr`: `SEConstant`, `SESymbol`, `SEKeyword`, `SEList`, **plus `SEReserved`** (reserved words in s-exprs, e.g. `_`/`as` in proofs) |
| `CmdResponse`/`GenResponse`/`CheckSatResponse`/`InfoResponse`/`ValuationPair`/`TValuationPair` | `CommandResponse` (`RSuccess`/`RUnsupported`/`RError`/`RCheckSat`/…), `CheckSatResponse` (`Sat`/`Unsat`/`Unknown`), `InfoResponse`, `ValuationPair`; get-assignment pairs are `[(Symbol, Bool)]` |

Behavioural differences to handle in `interpretFun` / `runCommand`:

- **`check-sat-assuming`** now parses to `[PropLiteral a]` (`PosLiteral`/
  `NegLiteral`), not `[Term]`. Adjust the handler accordingly.
- **`declare-fun`** is `DeclareFun !Symbol [Sort a] (Sort a) a` (unnamed arg
  sorts), matching the spec; `define-fun(-rec)` take a `FunctionDef`.
- The new AST **supports `match`, `declare-datatype(s)`, and `par`**, which the
  old fork lacked. Parsing no longer rejects them; the solver can still throw
  `Unsupported` where it does not implement them. Quantifiers parse too (the old
  `interpretFun` threw on `forall`/`exists`).

## What the new library does NOT reject that the old one may have

Documented benign supersets — verify toysolver inputs still behave:

- Unicode letters are allowed in **simple symbols** (so `あいうえお` needs no
  quoting); the `unicode-symbol.smt2` sample relies on this.
- `(push)` / `(pop)` without a numeral are read as `(push 1)` / `(pop 1)`.
- Numeric literals round-trip byte-for-byte (raw lexeme); use the interpreters
  in `Language.SMTLIB.Syntax.Constant` (`hexToInteger`, `binToInteger`,
  `decimalToScientific`) for their values.

All 30 vendored `samples/smt/*.smt2` (including toysolver's own) parse and
re-render idempotently, so the parser is at least as accepting as the old fork
on that corpus.

## Suggested migration steps

1. Add `language-smtlib` as a dependency of `toysolver` (and drop the `Smtlib`
   submodule once nothing imports it).
2. Rewrite `SMTLIB2Solver.hs`:
   - swap imports to `Language.SMTLIB.{Syntax,Parser,Printer}`;
   - update constructor names per the table above and switch `String` →
     `Text` (use `showSLString` where a `String` message is still needed);
   - update `interpretFun`/`valueToTerm`/`exprToTerm` to the new `Term`
     constructors; handle `TMatch` (reject as unsupported if not implemented).
3. Update `toysmt.hs`:
   - file load → `parseScript'` over `Data.Text.IO.readFile`;
   - REPL → `Language.SMTLIB.Reader.Handle` (`newHandleReader` + `readCommand`)
     for incremental input that prompts for continuation lines and never
     over-reads the pipe, or `frameCommand` for manual buffering.
4. Re-point or drop toysolver's `Test/Smtlib.hs` (the round-trip props now live
   in this repo's `test/`).

### Optional: a compatibility shim

If a big-bang rewrite is undesirable, add `Language.SMTLIB.Compat.Smtlib`
exposing `parseSource` / `parseCommand` / `showSL` and the old constructor names
(as pattern synonyms / converters) over the new `Text` AST, so toysolver
compiles with minimal edits and can be migrated incrementally. This was
considered in the plan but intentionally not built; add it only if the direct
migration proves too large.

## References

- New public API: `Language.SMTLIB` (umbrella), `…Parser`, `…Printer`,
  `…Reader`/`…Reader.Handle`, `…Parser.Response`.
- Old fork (for the mapping): `toysolver/Smtlib/Smtlib/Syntax/Syntax.hs`,
  `…/Syntax/ShowSL.hs`, `…/Parsers/*`.
