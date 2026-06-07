-- | Parsers for commands, options, info flags and prop-literals.
module Language.SMTLIB.Parser.Command
  ( pCommand
  , pScript
  , pOption
  , pInfoFlag
  , pPropLiteral
  ) where

import Data.Functor (($>))
import qualified Data.Text as T
import Text.Megaparsec

import Language.SMTLIB.Parser.Internal
import Language.SMTLIB.Parser.Term
import Language.SMTLIB.Syntax.Annotation (SrcSpan)
import Language.SMTLIB.Syntax.Command

-- | A whole script: zero or more commands.  (Leading whitespace is the caller's
-- responsibility; see "Language.SMTLIB.Parser".)
pScript :: P (Script SrcSpan)
pScript = many pCommand

-- | A top-level @command@.
--
-- The command keyword is read once as a single word and then dispatched on,
-- rather than attempting each alternative in turn.  This avoids re-scanning the
-- keyword (and the backtracking that goes with it) for every command — a large
-- saving on scripts dominated by a few command shapes (e.g. @assert@).
pCommand :: P (Command SrcSpan)
pCommand = withSpan $ do
  _ <- openP
  kw <- pAnyWord
  c <- case kw of
    "set-logic"               -> SetLogic <$> pSymbolRaw
    "set-option"              -> SetOption <$> pOption
    "set-info"                -> SetInfo <$> pAttribute
    "declare-sort-parameter"  -> DeclareSortParameter <$> pSymbolRaw
    "declare-sort"            -> DeclareSort <$> pSymbolRaw <*> numeral
    "declare-const"           -> DeclareConst <$> pSymbolRaw <*> pSort
    "define-const"            -> DefineConst <$> pSymbolRaw <*> pSort <*> pTerm
    "declare-datatypes"       -> DeclareDatatypes <$> parens (some pSortDec)
                                                  <*> parens (some pDatatypeDec)
    "declare-datatype"        -> DeclareDatatype <$> pSymbolRaw <*> pDatatypeDec
    "declare-fun"             -> DeclareFun <$> pSymbolRaw <*> parens (many pSort) <*> pSort
    "define-sort"             -> DefineSort <$> pSymbolRaw <*> parens (many pSymbolRaw) <*> pSort
    "define-fun-rec"          -> DefineFunRec <$> pFunctionDef
    "define-funs-rec"         -> DefineFunsRec <$> parens (some pFunctionDec)
                                              <*> parens (some pTerm)
    "define-fun"              -> DefineFun <$> pFunctionDef
    "push"                    -> Push <$> (numeral <|> pure 1)
    "pop"                     -> Pop <$> (numeral <|> pure 1)
    "reset-assertions"        -> pure ResetAssertions
    "reset"                   -> pure Reset
    "assert"                  -> Assert <$> pTerm
    "check-sat-assuming"      -> CheckSatAssuming <$> parens (many pPropLiteral)
    "check-sat"               -> pure CheckSat
    "get-assertions"          -> pure GetAssertions
    "get-assignment"          -> pure GetAssignment
    "get-info"                -> GetInfo <$> pInfoFlag
    "get-model"               -> pure GetModel
    "get-option"              -> GetOption <$> pKeyword
    "get-proof"               -> pure GetProof
    "get-unsat-assumptions"   -> pure GetUnsatAssumptions
    "get-unsat-core"          -> pure GetUnsatCore
    "get-value"               -> GetValue <$> parens (some pTerm)
    "echo"                    -> Echo <$> pStringLit
    "exit"                    -> pure Exit
    _                         -> fail ("unknown command: " ++ T.unpack kw)
  _ <- closeP
  pure c

-- | An @option@ for @set-option@.
pOption :: P (Option SrcSpan)
pOption = withSpan $ choice
  [ tok ":diagnostic-output-channel"    *> (DiagnosticOutputChannel <$> pStringLit)
  , tok ":global-declarations"          *> (GlobalDeclarations <$> pBool)
  , tok ":interactive-mode"             *> (InteractiveMode <$> pBool)
  , tok ":print-success"                *> (PrintSuccess <$> pBool)
  , tok ":produce-assertions"           *> (ProduceAssertions <$> pBool)
  , tok ":produce-assignments"          *> (ProduceAssignments <$> pBool)
  , tok ":produce-models"               *> (ProduceModels <$> pBool)
  , tok ":produce-proofs"               *> (ProduceProofs <$> pBool)
  , tok ":produce-unsat-assumptions"    *> (ProduceUnsatAssumptions <$> pBool)
  , tok ":produce-unsat-cores"          *> (ProduceUnsatCores <$> pBool)
  , tok ":random-seed"                  *> (RandomSeed <$> numeral)
  , tok ":regular-output-channel"       *> (RegularOutputChannel <$> pStringLit)
  , tok ":reproducible-resource-limit"  *> (ReproducibleResourceLimit <$> numeral)
  , tok ":verbosity"                    *> (Verbosity <$> numeral)
  , OptionAttribute <$> pAttribute
  ]

-- | An @info_flag@ for @get-info@.
pInfoFlag :: P (InfoFlag SrcSpan)
pInfoFlag = withSpan $ choice
  [ tok ":all-statistics"         $> AllStatistics
  , tok ":assertion-stack-levels" $> AssertionStackLevels
  , tok ":authors"                $> Authors
  , tok ":error-behavior"         $> ErrorBehaviorFlag
  , tok ":name"                   $> InfoName
  , tok ":reason-unknown"         $> ReasonUnknownFlag
  , tok ":version"                $> InfoVersion
  , InfoFlagKeyword <$> pKeyword
  ]

-- | A @prop_literal@: a symbol or @(not symbol)@.
pPropLiteral :: P (PropLiteral SrcSpan)
pPropLiteral = withSpan (pos <|> neg)
  where
    pos = PosLiteral <$> pSymbolRaw
    neg = parens (tok "not" *> (NegLiteral <$> pSymbolRaw))
