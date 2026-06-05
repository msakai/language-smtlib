-- | Declarations for sorts, datatypes and (recursive) function definitions.
module Language.SMTLIB.Syntax.Datatype
  ( SortDec(..)
  , SelectorDec(..)
  , ConstructorDec(..)
  , DatatypeDec(..)
  , FunctionDec(..)
  , FunctionDef(..)
  ) where

import Language.SMTLIB.Syntax.Annotation (Annotated(..))
import Language.SMTLIB.Syntax.Constant (Symbol)
import Language.SMTLIB.Syntax.Identifier (Sort)
import Language.SMTLIB.Syntax.Term (SortedVar, Term)

-- | A @sort_dec@ @(symbol numeral)@ heading a @declare-datatypes@.
data SortDec a = SortDec !Symbol !Integer a
  deriving (Show, Eq, Functor, Foldable, Traversable)

-- | A @selector_dec@ @(symbol sort)@.
data SelectorDec a = SelectorDec !Symbol (Sort a) a
  deriving (Show, Eq, Functor, Foldable, Traversable)

-- | A @constructor_dec@ @(symbol selector_dec*)@.
data ConstructorDec a = ConstructorDec !Symbol [SelectorDec a] a
  deriving (Show, Eq, Functor, Foldable, Traversable)

-- | A @datatype_dec@.  The first field holds the @par@ type variables; it is
-- empty for a non-parametric @(constructor_dec+)@ declaration and non-empty for
-- a @(par (u+) (constructor_dec+))@ declaration.
data DatatypeDec a = DatatypeDec [Symbol] [ConstructorDec a] a
  deriving (Show, Eq, Functor, Foldable, Traversable)

-- | A @function_dec@ @(symbol (sorted_var*) sort)@, used by @define-funs-rec@.
data FunctionDec a = FunctionDec !Symbol [SortedVar a] (Sort a) a
  deriving (Show, Eq, Functor, Foldable, Traversable)

-- | A @function_def@ @symbol (sorted_var*) sort term@, used by @define-fun@ and
-- @define-fun-rec@.
data FunctionDef a = FunctionDef !Symbol [SortedVar a] (Sort a) (Term a) a
  deriving (Show, Eq, Functor, Foldable, Traversable)

instance Annotated SortDec where
  ann (SortDec _ _ a) = a
  setAnn a (SortDec s n _) = SortDec s n a

instance Annotated SelectorDec where
  ann (SelectorDec _ _ a) = a
  setAnn a (SelectorDec s t _) = SelectorDec s t a

instance Annotated ConstructorDec where
  ann (ConstructorDec _ _ a) = a
  setAnn a (ConstructorDec s ss _) = ConstructorDec s ss a

instance Annotated DatatypeDec where
  ann (DatatypeDec _ _ a) = a
  setAnn a (DatatypeDec ps cs _) = DatatypeDec ps cs a

instance Annotated FunctionDec where
  ann (FunctionDec _ _ _ a) = a
  setAnn a (FunctionDec s vs r _) = FunctionDec s vs r a

instance Annotated FunctionDef where
  ann (FunctionDef _ _ _ _ a) = a
  setAnn a (FunctionDef s vs r t _) = FunctionDef s vs r t a
