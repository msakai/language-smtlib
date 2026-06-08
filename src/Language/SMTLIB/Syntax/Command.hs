-- | Top-level commands of an SMT-LIB 2 script.
module Language.SMTLIB.Syntax.Command
  ( Command(..)
  , Option(..)
  , InfoFlag(..)
  , Script
  ) where

import Data.Hashable (Hashable)
import Data.Text (Text)
import GHC.Generics (Generic)

import Language.SMTLIB.Syntax.Annotation (Annotated(..))
import Language.SMTLIB.Syntax.Attribute (Attribute)
import Language.SMTLIB.Syntax.Constant (Keyword, Symbol)
import Language.SMTLIB.Syntax.Datatype
  (DatatypeDec, FunctionDec, FunctionDef, SortDec)
import Language.SMTLIB.Syntax.Identifier (Sort)
import Language.SMTLIB.Syntax.Term (Term)

-- | An @option@ for @set-option@.
data Option a
  = DiagnosticOutputChannel    !Text          a
  | GlobalDeclarations         !Bool          a
  | InteractiveMode            !Bool          a
  | PrintSuccess               !Bool          a
  | ProduceAssertions          !Bool          a
  | ProduceAssignments         !Bool          a
  | ProduceModels              !Bool          a
  | ProduceProofs              !Bool          a
  | ProduceUnsatAssumptions    !Bool          a
  | ProduceUnsatCores          !Bool          a
  | RandomSeed                 !Integer       a
  | RegularOutputChannel       !Text          a
  | ReproducibleResourceLimit  !Integer       a
  | Verbosity                  !Integer       a
  | OptionAttribute            (Attribute a)  a
  deriving (Show, Eq, Ord, Functor, Foldable, Traversable, Generic)

-- | An @info_flag@ for @get-info@.
data InfoFlag a
  = AllStatistics       a
  | AssertionStackLevels a
  | Authors             a
  | ErrorBehaviorFlag   a
  | InfoName            a
  | ReasonUnknownFlag   a
  | InfoVersion         a
  | InfoFlagKeyword !Keyword a
  deriving (Show, Eq, Ord, Functor, Foldable, Traversable, Generic)

-- | A top-level @command@.
data Command a
  = SetLogic         !Symbol                            a
  | SetOption        (Option a)                         a
  | SetInfo          (Attribute a)                      a
  | DeclareSort      !Symbol !Integer                   a
  | DeclareSortParameter !Symbol                        a  -- ^ SMT-LIB 2.7
  | DefineSort       !Symbol [Symbol] (Sort a)          a
  | DeclareConst     !Symbol (Sort a)                   a
  | DefineConst      !Symbol (Sort a) (Term a)          a  -- ^ SMT-LIB 2.7
  | DeclareFun       !Symbol [Sort a] (Sort a)          a
  | DefineFun        (FunctionDef a)                    a
  | DefineFunRec     (FunctionDef a)                    a
  | DefineFunsRec    [FunctionDec a] [Term a]           a
  | DeclareDatatype  !Symbol (DatatypeDec a)            a
  | DeclareDatatypes [SortDec a] [DatatypeDec a]        a
  | Push             !Integer                           a
  | Pop              !Integer                           a
  | Reset            a
  | ResetAssertions  a
  | Assert           (Term a)                           a
  | CheckSat         a
  | CheckSatAssuming [Term a]                           a  -- ^ assumptions: arbitrary Bool terms (SMT-LIB 2.7; was @prop_literal@)
  | GetAssertions    a
  | GetModel         a
  | GetProof         a
  | GetUnsatCore     a
  | GetUnsatAssumptions a
  | GetValue         [Term a]                           a
  | GetAssignment    a
  | GetOption        !Keyword                           a
  | GetInfo          (InfoFlag a)                       a
  | Echo             !Text                              a
  | Exit             a
  deriving (Show, Eq, Ord, Functor, Foldable, Traversable, Generic)

-- | A script is a sequence of commands.
type Script a = [Command a]

instance Hashable a => Hashable (Option a)
instance Hashable a => Hashable (InfoFlag a)
instance Hashable a => Hashable (Command a)

instance Annotated Option where
  ann = \case
    DiagnosticOutputChannel _ a   -> a
    GlobalDeclarations _ a        -> a
    InteractiveMode _ a           -> a
    PrintSuccess _ a              -> a
    ProduceAssertions _ a         -> a
    ProduceAssignments _ a        -> a
    ProduceModels _ a             -> a
    ProduceProofs _ a             -> a
    ProduceUnsatAssumptions _ a   -> a
    ProduceUnsatCores _ a         -> a
    RandomSeed _ a                -> a
    RegularOutputChannel _ a      -> a
    ReproducibleResourceLimit _ a -> a
    Verbosity _ a                 -> a
    OptionAttribute _ a           -> a
  setAnn a = \case
    DiagnosticOutputChannel x _   -> DiagnosticOutputChannel x a
    GlobalDeclarations x _        -> GlobalDeclarations x a
    InteractiveMode x _           -> InteractiveMode x a
    PrintSuccess x _              -> PrintSuccess x a
    ProduceAssertions x _         -> ProduceAssertions x a
    ProduceAssignments x _        -> ProduceAssignments x a
    ProduceModels x _             -> ProduceModels x a
    ProduceProofs x _             -> ProduceProofs x a
    ProduceUnsatAssumptions x _   -> ProduceUnsatAssumptions x a
    ProduceUnsatCores x _         -> ProduceUnsatCores x a
    RandomSeed x _                -> RandomSeed x a
    RegularOutputChannel x _      -> RegularOutputChannel x a
    ReproducibleResourceLimit x _ -> ReproducibleResourceLimit x a
    Verbosity x _                 -> Verbosity x a
    OptionAttribute x _           -> OptionAttribute x a

instance Annotated InfoFlag where
  ann = \case
    AllStatistics a        -> a
    AssertionStackLevels a -> a
    Authors a              -> a
    ErrorBehaviorFlag a    -> a
    InfoName a             -> a
    ReasonUnknownFlag a    -> a
    InfoVersion a          -> a
    InfoFlagKeyword _ a    -> a
  setAnn a = \case
    AllStatistics _        -> AllStatistics a
    AssertionStackLevels _ -> AssertionStackLevels a
    Authors _              -> Authors a
    ErrorBehaviorFlag _    -> ErrorBehaviorFlag a
    InfoName _             -> InfoName a
    ReasonUnknownFlag _    -> ReasonUnknownFlag a
    InfoVersion _          -> InfoVersion a
    InfoFlagKeyword k _    -> InfoFlagKeyword k a

instance Annotated Command where
  ann = \case
    SetLogic _ a            -> a
    SetOption _ a           -> a
    SetInfo _ a             -> a
    DeclareSort _ _ a       -> a
    DeclareSortParameter _ a -> a
    DefineSort _ _ _ a      -> a
    DeclareConst _ _ a      -> a
    DefineConst _ _ _ a     -> a
    DeclareFun _ _ _ a      -> a
    DefineFun _ a           -> a
    DefineFunRec _ a        -> a
    DefineFunsRec _ _ a     -> a
    DeclareDatatype _ _ a   -> a
    DeclareDatatypes _ _ a  -> a
    Push _ a                -> a
    Pop _ a                 -> a
    Reset a                 -> a
    ResetAssertions a       -> a
    Assert _ a              -> a
    CheckSat a              -> a
    CheckSatAssuming _ a    -> a
    GetAssertions a         -> a
    GetModel a              -> a
    GetProof a              -> a
    GetUnsatCore a          -> a
    GetUnsatAssumptions a   -> a
    GetValue _ a            -> a
    GetAssignment a         -> a
    GetOption _ a           -> a
    GetInfo _ a             -> a
    Echo _ a                -> a
    Exit a                  -> a
  setAnn a = \case
    SetLogic x _            -> SetLogic x a
    SetOption x _           -> SetOption x a
    SetInfo x _             -> SetInfo x a
    DeclareSort x y _       -> DeclareSort x y a
    DeclareSortParameter x _ -> DeclareSortParameter x a
    DefineSort x y z _      -> DefineSort x y z a
    DeclareConst x y _      -> DeclareConst x y a
    DefineConst x y z _     -> DefineConst x y z a
    DeclareFun x y z _      -> DeclareFun x y z a
    DefineFun x _           -> DefineFun x a
    DefineFunRec x _        -> DefineFunRec x a
    DefineFunsRec x y _     -> DefineFunsRec x y a
    DeclareDatatype x y _   -> DeclareDatatype x y a
    DeclareDatatypes x y _  -> DeclareDatatypes x y a
    Push x _                -> Push x a
    Pop x _                 -> Pop x a
    Reset _                 -> Reset a
    ResetAssertions _       -> ResetAssertions a
    Assert x _              -> Assert x a
    CheckSat _              -> CheckSat a
    CheckSatAssuming x _    -> CheckSatAssuming x a
    GetAssertions _         -> GetAssertions a
    GetModel _              -> GetModel a
    GetProof _              -> GetProof a
    GetUnsatCore _          -> GetUnsatCore a
    GetUnsatAssumptions _   -> GetUnsatAssumptions a
    GetValue x _            -> GetValue x a
    GetAssignment _         -> GetAssignment a
    GetOption x _           -> GetOption x a
    GetInfo x _             -> GetInfo x a
    Echo x _                -> Echo x a
    Exit _                  -> Exit a
