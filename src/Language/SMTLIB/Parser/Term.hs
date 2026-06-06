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

import Data.Functor (($>))
import Text.Megaparsec

import Language.SMTLIB.Parser.Internal
import Language.SMTLIB.Syntax.Annotation (SrcSpan)
import Language.SMTLIB.Syntax.Constant (Symbol)
import Language.SMTLIB.Syntax.Datatype
import Language.SMTLIB.Syntax.Term

-- | A @term@.
pTerm :: P (Term SrcSpan)
pTerm = withSpan $ choice
  [ TConstant  <$> pSpecConstant
  , try (TQualIdent <$> pQualIdentifier)   -- symbol, (_ ..) or (as ..) used directly
  , parenCompound
  ]

-- | A parenthesised compound term: a binder, @match@, @!@, or an application.
-- The opening paren is consumed here; the leading 'try' in 'pTerm' has already
-- ruled out a bare qualified identifier.
parenCompound :: P (SrcSpan -> Term SrcSpan)
parenCompound = do
  _ <- openP
  r <- choice
    [ tok "let"    *> (TLet    <$> parens (some pVarBinding) <*> pTerm)
    , tok "lambda" *> (TLambda <$> parens (some pSortedVar)  <*> pTerm)
    , tok "forall" *> (TForall <$> parens (some pSortedVar)  <*> pTerm)
    , tok "exists" *> (TExists <$> parens (some pSortedVar)  <*> pTerm)
    , tok "match"  *> (TMatch  <$> pTerm <*> parens (some pMatchCase))
    , tok "!"      *> (TAnnot  <$> pTerm <*> some pAttribute)
    , TApp <$> pQualIdentifier <*> some pTerm
    ]
  _ <- closeP
  pure r

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
