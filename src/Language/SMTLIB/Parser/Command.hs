-- | Parsers for commands, options, info flags and prop-literals.
module Language.SMTLIB.Parser.Command
  ( pCommand
  , pScript
  , pOption
  , pInfoFlag
  , pPropLiteral
  ) where

import Data.Functor (($>))
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
pCommand :: P (Command SrcSpan)
pCommand = withSpan $ do
  _ <- openP
  c <- choice
    [ tok "set-logic"          *> (SetLogic <$> pSymbolRaw)
    , tok "set-option"         *> (SetOption <$> pOption)
    , tok "set-info"           *> (SetInfo <$> pAttribute)
    , tok "declare-sort"       *> (DeclareSort <$> pSymbolRaw <*> numeral)
    , tok "declare-const"      *> (DeclareConst <$> pSymbolRaw <*> pSort)
    , tok "declare-datatypes"  *> (DeclareDatatypes <$> parens (some pSortDec)
                                                    <*> parens (some pDatatypeDec))
    , tok "declare-datatype"   *> (DeclareDatatype <$> pSymbolRaw <*> pDatatypeDec)
    , tok "declare-fun"        *> (DeclareFun <$> pSymbolRaw <*> parens (many pSort) <*> pSort)
    , tok "define-sort"        *> (DefineSort <$> pSymbolRaw <*> parens (many pSymbolRaw) <*> pSort)
    , tok "define-fun-rec"     *> (DefineFunRec <$> pFunctionDef)
    , tok "define-funs-rec"    *> (DefineFunsRec <$> parens (some pFunctionDec)
                                                <*> parens (some pTerm))
    , tok "define-fun"         *> (DefineFun <$> pFunctionDef)
    , tok "push"               *> (Push <$> (numeral <|> pure 1))
    , tok "pop"                *> (Pop <$> (numeral <|> pure 1))
    , tok "reset-assertions"   $> ResetAssertions
    , tok "reset"              $> Reset
    , tok "assert"             *> (Assert <$> pTerm)
    , tok "check-sat-assuming" *> (CheckSatAssuming <$> parens (many pPropLiteral))
    , tok "check-sat"          $> CheckSat
    , tok "get-assertions"     $> GetAssertions
    , tok "get-assignment"     $> GetAssignment
    , tok "get-info"           *> (GetInfo <$> pInfoFlag)
    , tok "get-model"          $> GetModel
    , tok "get-option"         *> (GetOption <$> pKeyword)
    , tok "get-proof"          $> GetProof
    , tok "get-unsat-assumptions" $> GetUnsatAssumptions
    , tok "get-unsat-core"     $> GetUnsatCore
    , tok "get-value"          *> (GetValue <$> parens (some pTerm))
    , tok "echo"               *> (Echo <$> pStringLit)
    , tok "exit"               $> Exit
    ]
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
