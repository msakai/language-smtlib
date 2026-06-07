-- | Parsers for solver command responses.
--
-- Many responses share the @( ... )@ shape, so they cannot be told apart
-- without knowing which command they answer.  This module therefore exposes a
-- per-response parser for each command, plus 'pCommandResponse' for the
-- context-free responses (@success@, @unsupported@, @sat@\/@unsat@\/@unknown@
-- and @(error ...)@).
module Language.SMTLIB.Parser.Response
  ( -- * Combinators
    pCommandResponse
  , pGeneralResponse
  , pCheckSatResponse
  , pGetValueResponse
  , pGetModelResponse
  , pGetAssignmentResponse
  , pGetUnsatCoreResponse
  , pGetUnsatAssumptionsResponse
  , pGetAssertionsResponse
  , pGetInfoResponse
  , pGetProofResponse
  , pGetOptionResponse
  , pInfoResponse
  , pValuationPair
  , pModelResponse
  ) where

import Data.Functor (($>))
import Text.Megaparsec

import Language.SMTLIB.Parser.Internal
import Language.SMTLIB.Parser.Term (pFunctionDec, pFunctionDef, pTerm)
import Language.SMTLIB.Syntax.Annotation (SrcSpan)
import Language.SMTLIB.Syntax.Attribute (AttributeValue, SExpr)
import Language.SMTLIB.Syntax.Constant (Symbol)
import Language.SMTLIB.Syntax.Response
import Language.SMTLIB.Syntax.Term (Term)

-- | The context-free responses (@success@, @unsupported@, the @check-sat@
-- answers, and @(error ...)@).  Use the specific parsers below for
-- list-shaped responses.
pCommandResponse :: P (CommandResponse SrcSpan)
pCommandResponse = choice
  [ tok "success"     $> RSuccess
  , tok "unsupported" $> RUnsupported
  , tok "sat"         $> RCheckSat Sat
  , tok "unsat"       $> RCheckSat Unsat
  , tok "unknown"     $> RCheckSat Unknown
  , parens (tok "error" *> (RError <$> pStringLit))
  ]

-- | @success | unsupported | (error string)@.
pGeneralResponse :: P (CommandResponse SrcSpan)
pGeneralResponse = choice
  [ tok "success"     $> RSuccess
  , tok "unsupported" $> RUnsupported
  , parens (tok "error" *> (RError <$> pStringLit))
  ]

-- | @sat | unsat | unknown@.
pCheckSatResponse :: P CheckSatResponse
pCheckSatResponse = choice
  [ tok "sat"     $> Sat
  , tok "unsat"   $> Unsat
  , tok "unknown" $> Unknown
  ]

-- | @( (term value)+ )@.
pGetValueResponse :: P [ValuationPair SrcSpan]
pGetValueResponse = parens (some pValuationPair)

-- | A @(term value)@ pair.
pValuationPair :: P (ValuationPair SrcSpan)
pValuationPair = parens (ValuationPair <$> pTerm <*> pTerm)

-- | @( model_response* )@, tolerating a legacy leading @model@ keyword.
pGetModelResponse :: P [ModelResponse SrcSpan]
pGetModelResponse = parens (optional (tok "model") *> many pModelResponse)

-- | A single @model_response@ definition (@define-fun@\/@-rec@\/@-funs-rec@).
pModelResponse :: P (ModelResponse SrcSpan)
pModelResponse = parens $ choice
  [ tok "define-fun-rec"  *> (MRDefineFunRec <$> pFunctionDef)
  , tok "define-funs-rec" *> (MRDefineFunsRec <$> parens (some pFunctionDec)
                                              <*> parens (some pTerm))
  , tok "define-fun"      *> (MRDefineFun <$> pFunctionDef)
  ]

-- | @( (symbol b_value)* )@.
pGetAssignmentResponse :: P [(Symbol, Bool)]
pGetAssignmentResponse = parens (many (parens ((,) <$> pSymbolRaw <*> pBool)))

-- | @( symbol* )@.
pGetUnsatCoreResponse :: P [Symbol]
pGetUnsatCoreResponse = parens (many pSymbolRaw)

-- | @( term* )@ (SMT-LIB 2.7 generalised assumptions: arbitrary Bool terms).
pGetUnsatAssumptionsResponse :: P [Term SrcSpan]
pGetUnsatAssumptionsResponse = parens (many pTerm)

-- | @( term* )@.
pGetAssertionsResponse :: P [Term SrcSpan]
pGetAssertionsResponse = parens (many pTerm)

-- | @( info_response+ )@.
pGetInfoResponse :: P [InfoResponse SrcSpan]
pGetInfoResponse = parens (some pInfoResponse)

-- | A single @info_response@ entry.
pInfoResponse :: P (InfoResponse SrcSpan)
pInfoResponse = choice
  [ tok ":assertion-stack-levels" *> (IRAssertionStackLevels <$> numeral)
  , tok ":authors"        *> (IRAuthors <$> pStringLit)
  , tok ":error-behavior" *> (IRErrorBehavior <$> pErrorBehavior)
  , tok ":name"           *> (IRName <$> pStringLit)
  , tok ":reason-unknown" *> (IRReasonUnknown <$> pReasonUnknown)
  , tok ":version"        *> (IRVersion <$> pStringLit)
  , IRAttribute <$> pAttribute
  ]

pErrorBehavior :: P ErrorBehavior
pErrorBehavior = choice
  [ tok "immediate-exit"      $> ImmediateExit
  , tok "continued-execution" $> ContinuedExecution
  ]

pReasonUnknown :: P (ReasonUnknown SrcSpan)
pReasonUnknown = choice
  [ tok "memout"     $> RUMemout
  , tok "incomplete" $> RUIncomplete
  , RUOther <$> pSExpr
  ]

-- | A single @s_expr@.
pGetProofResponse :: P (SExpr SrcSpan)
pGetProofResponse = pSExpr

-- | An @attribute_value@.
pGetOptionResponse :: P (AttributeValue SrcSpan)
pGetOptionResponse = pAttributeValue
