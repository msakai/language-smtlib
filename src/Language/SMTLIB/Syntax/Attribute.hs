-- | S-expressions and attributes, as used by @set-info@, @set-option@, the
-- @(! term ...)@ annotation form and solver responses.
module Language.SMTLIB.Syntax.Attribute
  ( SExpr(..)
  , AttributeValue(..)
  , Attribute(..)
  ) where

import Language.SMTLIB.Syntax.Annotation (Annotated(..))
import Language.SMTLIB.Syntax.Constant (Keyword, SpecConstant, Symbol)

-- | An @s_expr@.
data SExpr a
  = SEConstant (SpecConstant a) a
  | SESymbol   !Symbol          a
  | SEKeyword  !Keyword         a
  | SEReserved !Symbol          a  -- ^ a reserved word appearing in an s-expr (e.g. @_@, @as@)
  | SEList     [SExpr a]        a
  deriving (Show, Eq, Functor, Foldable, Traversable)

-- | An @attribute_value@.
data AttributeValue a
  = AVConstant (SpecConstant a) a
  | AVSymbol   !Symbol          a
  | AVSExpr    [SExpr a]        a
  deriving (Show, Eq, Functor, Foldable, Traversable)

-- | An @attribute@: a keyword, optionally carrying a value.
data Attribute a
  = Attribute     !Keyword                    a
  | AttributeWith !Keyword (AttributeValue a) a
  deriving (Show, Eq, Functor, Foldable, Traversable)

instance Annotated SExpr where
  ann = \case
    SEConstant _ a -> a
    SESymbol _ a   -> a
    SEKeyword _ a  -> a
    SEReserved _ a -> a
    SEList _ a     -> a
  setAnn a = \case
    SEConstant x _ -> SEConstant x a
    SESymbol x _   -> SESymbol x a
    SEKeyword x _  -> SEKeyword x a
    SEReserved x _ -> SEReserved x a
    SEList x _     -> SEList x a

instance Annotated AttributeValue where
  ann = \case
    AVConstant _ a -> a
    AVSymbol _ a   -> a
    AVSExpr _ a    -> a
  setAnn a = \case
    AVConstant x _ -> AVConstant x a
    AVSymbol x _   -> AVSymbol x a
    AVSExpr x _    -> AVSExpr x a

instance Annotated Attribute where
  ann = \case
    Attribute _ a       -> a
    AttributeWith _ _ a -> a
  setAnn a = \case
    Attribute k _       -> Attribute k a
    AttributeWith k v _ -> AttributeWith k v a
