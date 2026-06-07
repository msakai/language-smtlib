-- | Parsers for terms (with their binders and the @match@ form) and for the
-- declaration shapes built on top of them: sorted vars, datatype declarations
-- and function definitions.
module Language.SMTLIB.Parser.Term
  ( pTerm
  , pVarBinding
  , pSortedVar
  , pPattern
  , pMatchCase
  , pSortDec
  , pSelectorDec
  , pConstructorDec
  , pDatatypeDec
  , pFunctionDec
  , pFunctionDef
  ) where

import Data.Char (isDigit)
import Data.Functor (($>))
import Text.Megaparsec

import Language.SMTLIB.Parser.Internal
import Language.SMTLIB.Syntax.Annotation (SrcSpan)
import Language.SMTLIB.Syntax.Constant (Symbol)
import Language.SMTLIB.Syntax.Datatype
import Language.SMTLIB.Syntax.Term

-- | A @term@.
--
-- The first character selects the form directly instead of attempting and
-- rolling back alternatives: a non-paren term is a spec-constant (digit, @#@ or
-- @\"@) or a bare symbol; a paren term is dispatched by 'parenCompound'.
pTerm :: P (Term SrcSpan)
pTerm = withSpan $ do
  c <- lookAhead anySingle
  case c of
    '(' -> parenCompound
    _ | isConstStart c -> TConstant  <$> pSpecConstant
      | otherwise      -> TQualIdent <$> pQualIdentifier
  where
    isConstStart x = isDigit x || x == '#' || x == '"'

-- | A parenthesised compound term: a binder
-- (@let@\/@lambda@\/@forall@\/@exists@), @match@, @!@, a qualified identifier
-- used directly (@(as ...)@ or @(_ ...)@), or an application.
--
-- The head word immediately after the @(@ is peeked (without committing) to
-- choose the form, so no alternative has to be parsed and rolled back.  The
-- @(as ...)@ \/ @(_ ...)@ cases delegate to 'pQualIdentifier', which consumes
-- the paren itself; the other cases consume it here.
parenCompound :: P (SrcSpan -> Term SrcSpan)
parenCompound = do
  mw <- lookAhead (openP *> optional pAnyWord)
  case mw of
    Just "let"    -> binder (TLet    <$> parens (some pVarBinding) <*> pTerm)
    Just "lambda" -> binder (TLambda <$> parens (some pSortedVar)  <*> pTerm)
    Just "forall" -> binder (TForall <$> parens (some pSortedVar)  <*> pTerm)
    Just "exists" -> binder (TExists <$> parens (some pSortedVar)  <*> pTerm)
    Just "match"  -> binder (TMatch  <$> pTerm <*> parens (some pMatchCase))
    Just "!"      -> binder (TAnnot  <$> pTerm <*> some pAttribute)
    Just "as"     -> TQualIdent <$> pQualIdentifier
    Just "_"      -> TQualIdent <$> pQualIdentifier
    _             -> openP *> (TApp <$> pQualIdentifier <*> some pTerm) <* closeP
  where
    -- consume @(@ and the (already-peeked) head keyword, then the body
    binder body = openP *> pAnyWord *> body <* closeP

-- | A @var_binding@ @(symbol term)@.
pVarBinding :: P (VarBinding SrcSpan)
pVarBinding = withSpan (parens (VarBinding <$> pSymbolRaw <*> pTerm))

-- | A @sorted_var@ @(symbol sort)@.
pSortedVar :: P (SortedVar SrcSpan)
pSortedVar = withSpan (parens (SortedVar <$> pSymbolRaw <*> pSort))

-- | A @pattern@: a single symbol, or @(constructor x1 ... xn)@.  The bound
-- variables (and a whole single-symbol pattern) may be the @_@ wildcard
-- (SMT-LIB 2.7); the constructor symbol itself may not.
pPattern :: P (Pattern SrcSpan)
pPattern = withSpan (pvar <|> ctor)
  where
    pvar = PVar <$> pPatternSymbol
    ctor = parens (PCtor <$> pSymbolRaw <*> some pPatternSymbol)

-- | A symbol in a @match@ pattern binding position: an ordinary symbol or the
-- @_@ wildcard.  @_@ is otherwise a reserved word, so 'pSymbolRaw' rejects it.
pPatternSymbol :: P Symbol
pPatternSymbol = pSymbolRaw <|> (tok "_" $> "_")

-- | A @match_case@ @(pattern term)@.
pMatchCase :: P (MatchCase SrcSpan)
pMatchCase = withSpan (parens (MatchCase <$> pPattern <*> pTerm))

-- | A @sort_dec@ @(symbol numeral)@.
pSortDec :: P (SortDec SrcSpan)
pSortDec = withSpan (parens (SortDec <$> pSymbolRaw <*> numeral))

-- | A @selector_dec@ @(symbol sort)@.
pSelectorDec :: P (SelectorDec SrcSpan)
pSelectorDec = withSpan (parens (SelectorDec <$> pSymbolRaw <*> pSort))

-- | A @constructor_dec@ @(symbol selector_dec*)@.
pConstructorDec :: P (ConstructorDec SrcSpan)
pConstructorDec = withSpan (parens (ConstructorDec <$> pSymbolRaw <*> many pSelectorDec))

-- | A @datatype_dec@: @(constructor_dec+)@ or @(par (u+) (constructor_dec+))@.
pDatatypeDec :: P (DatatypeDec SrcSpan)
pDatatypeDec = withSpan $ do
  _ <- openP
  r <- par <|> nonPar
  _ <- closeP
  pure r
  where
    par    = tok "par" *> (DatatypeDec <$> parens (some pSymbolRaw)
                                       <*> parens (some pConstructorDec))
    nonPar = DatatypeDec [] <$> some pConstructorDec

-- | A @function_dec@ @(symbol (sorted_var*) sort)@.
pFunctionDec :: P (FunctionDec SrcSpan)
pFunctionDec =
  withSpan (parens (FunctionDec <$> pSymbolRaw
                                <*> parens (many pSortedVar)
                                <*> pSort))

-- | A @function_def@ @symbol (sorted_var*) sort term@ (no surrounding parens).
pFunctionDef :: P (FunctionDef SrcSpan)
pFunctionDef =
  withSpan (FunctionDef <$> pSymbolRaw
                        <*> parens (many pSortedVar)
                        <*> pSort
                        <*> pTerm)
