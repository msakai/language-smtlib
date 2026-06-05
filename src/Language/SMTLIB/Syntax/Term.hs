-- | Terms and their binders, including the SMT-LIB 2.6 @match@ form.
module Language.SMTLIB.Syntax.Term
  ( Term(..)
  , VarBinding(..)
  , SortedVar(..)
  , Pattern(..)
  , MatchCase(..)
  ) where

import Language.SMTLIB.Syntax.Annotation (Annotated(..))
import Language.SMTLIB.Syntax.Attribute (Attribute)
import Language.SMTLIB.Syntax.Constant (SpecConstant, Symbol)
import Language.SMTLIB.Syntax.Identifier (QualIdentifier, Sort)

-- | A @term@.
data Term a
  = TConstant  (SpecConstant a)              a
  | TQualIdent (QualIdentifier a)            a
  | TApp       (QualIdentifier a) [Term a]   a  -- ^ function application; args non-empty
  | TLet       [VarBinding a] (Term a)       a
  | TForall    [SortedVar a]  (Term a)       a
  | TExists    [SortedVar a]  (Term a)       a
  | TMatch     (Term a) [MatchCase a]        a
  | TAnnot     (Term a) [Attribute a]        a  -- ^ @(! term attr ...)@; attrs non-empty
  deriving (Show, Eq, Functor, Foldable, Traversable)

-- | A @var_binding@ @(symbol term)@ of a @let@.
data VarBinding a = VarBinding !Symbol (Term a) a
  deriving (Show, Eq, Functor, Foldable, Traversable)

-- | A @sorted_var@ @(symbol sort)@.
data SortedVar a = SortedVar !Symbol (Sort a) a
  deriving (Show, Eq, Functor, Foldable, Traversable)

-- | A @pattern@ of a @match@ case: either a single variable\/nullary
-- constructor symbol, or @(constructor x1 ... xn)@.
data Pattern a
  = PVar  !Symbol           a
  | PCtor !Symbol [Symbol]  a
  deriving (Show, Eq, Functor, Foldable, Traversable)

-- | A @match_case@ @(pattern term)@.
data MatchCase a = MatchCase (Pattern a) (Term a) a
  deriving (Show, Eq, Functor, Foldable, Traversable)

instance Annotated Term where
  ann = \case
    TConstant _ a  -> a
    TQualIdent _ a -> a
    TApp _ _ a     -> a
    TLet _ _ a     -> a
    TForall _ _ a  -> a
    TExists _ _ a  -> a
    TMatch _ _ a   -> a
    TAnnot _ _ a   -> a
  setAnn a = \case
    TConstant x _  -> TConstant x a
    TQualIdent x _ -> TQualIdent x a
    TApp f x _     -> TApp f x a
    TLet b t _     -> TLet b t a
    TForall v t _  -> TForall v t a
    TExists v t _  -> TExists v t a
    TMatch t c _   -> TMatch t c a
    TAnnot t x _   -> TAnnot t x a

instance Annotated VarBinding where
  ann (VarBinding _ _ a) = a
  setAnn a (VarBinding s t _) = VarBinding s t a

instance Annotated SortedVar where
  ann (SortedVar _ _ a) = a
  setAnn a (SortedVar s t _) = SortedVar s t a

instance Annotated Pattern where
  ann = \case
    PVar _ a    -> a
    PCtor _ _ a -> a
  setAnn a = \case
    PVar s _    -> PVar s a
    PCtor s x _ -> PCtor s x a

instance Annotated MatchCase where
  ann (MatchCase _ _ a) = a
  setAnn a (MatchCase p t _) = MatchCase p t a
