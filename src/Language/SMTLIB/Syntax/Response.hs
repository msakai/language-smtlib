-- | Solver command responses (the output side of the protocol).
module Language.SMTLIB.Syntax.Response
  ( CheckSatResponse(..)
  , ErrorBehavior(..)
  , ReasonUnknown(..)
  , InfoResponse(..)
  , ValuationPair(..)
  , ModelResponse(..)
  , CommandResponse(..)
  ) where

import Data.Hashable (Hashable)
import Data.Text (Text)
import GHC.Generics (Generic)

import Language.SMTLIB.Syntax.Attribute (Attribute, AttributeValue, SExpr)
import Language.SMTLIB.Syntax.Constant (Symbol)
import Language.SMTLIB.Syntax.Datatype (FunctionDec, FunctionDef)
import Language.SMTLIB.Syntax.Term (Term)

-- | The response to @check-sat@.
data CheckSatResponse = Sat | Unsat | Unknown
  deriving (Show, Eq, Ord, Generic)

-- | The @:error-behavior@ of a solver.
data ErrorBehavior = ImmediateExit | ContinuedExecution
  deriving (Show, Eq, Ord, Generic)

-- | The @:reason-unknown@ explanation.
data ReasonUnknown a
  = RUMemout
  | RUIncomplete
  | RUOther (SExpr a)
  deriving (Show, Eq, Ord, Functor, Foldable, Traversable, Generic)

-- | A single entry of a @get-info@ response.
data InfoResponse a
  = IRAssertionStackLevels !Integer
  | IRAuthors !Text
  | IRErrorBehavior ErrorBehavior
  | IRName !Text
  | IRReasonUnknown (ReasonUnknown a)
  | IRVersion !Text
  | IRAttribute (Attribute a)
  deriving (Show, Eq, Ord, Functor, Foldable, Traversable, Generic)

-- | A @(term value)@ pair of a @get-value@ response.
data ValuationPair a = ValuationPair (Term a) (Term a)
  deriving (Show, Eq, Ord, Functor, Foldable, Traversable, Generic)

-- | A single definition of a @get-model@ response.
data ModelResponse a
  = MRDefineFun (FunctionDef a)
  | MRDefineFunRec (FunctionDef a)
  | MRDefineFunsRec [FunctionDec a] [Term a]
  deriving (Show, Eq, Ord, Functor, Foldable, Traversable, Generic)

-- | A solver's response to a command.  Which constructor a given solver emits
-- depends on the command it answers; the parsers in
-- "Language.SMTLIB.Parser.Response" therefore offer both a general parser and
-- per-command parsers.
data CommandResponse a
  = RSuccess
  | RUnsupported
  | RError !Text
  | RCheckSat CheckSatResponse
  | REcho !Text
  | RGetAssertions [Term a]
  | RGetAssignment [(Symbol, Bool)]
  | RGetInfo [InfoResponse a]
  | RGetModel [ModelResponse a]
  | RGetOption (AttributeValue a)
  | RGetProof (SExpr a)
  | RGetUnsatAssumptions [Term a]
  | RGetUnsatCore [Symbol]
  | RGetValue [ValuationPair a]
  deriving (Show, Eq, Ord, Functor, Foldable, Traversable, Generic)

instance Hashable CheckSatResponse
instance Hashable ErrorBehavior
instance Hashable a => Hashable (ReasonUnknown a)
instance Hashable a => Hashable (InfoResponse a)
instance Hashable a => Hashable (ValuationPair a)
instance Hashable a => Hashable (ModelResponse a)
instance Hashable a => Hashable (CommandResponse a)
