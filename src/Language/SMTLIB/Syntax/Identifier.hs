-- | Identifiers, qualified identifiers and sorts.
module Language.SMTLIB.Syntax.Identifier
  ( Identifier(..)
  , QualIdentifier(..)
  , Sort(..)
  , pattern Symbol
  ) where

import Language.SMTLIB.Syntax.Annotation (Annotated(..))
import Language.SMTLIB.Syntax.Constant (Index, Symbol)

-- | An @identifier@: a symbol optionally followed by a non-empty list of
-- indices, in which case it prints as @(_ sym i ...)@.
data Identifier a = Identifier !Symbol [Index a] a
  deriving (Show, Eq, Functor, Foldable, Traversable)

-- | A simple (non-indexed) identifier.
pattern Symbol :: Symbol -> Identifier ()
pattern Symbol s = Identifier s [] ()

-- | A @sort@: an identifier applied to zero or more argument sorts.
data Sort a = Sort (Identifier a) [Sort a] a
  deriving (Show, Eq, Functor, Foldable, Traversable)

-- | A @qual_identifier@: an identifier, optionally annotated with a result sort
-- via @(as id sort)@.
data QualIdentifier a
  = QIdentifier   (Identifier a)          a
  | QIdentifierAs (Identifier a) (Sort a) a
  deriving (Show, Eq, Functor, Foldable, Traversable)

instance Annotated Identifier where
  ann (Identifier _ _ a) = a
  setAnn a (Identifier s ix _) = Identifier s ix a

instance Annotated Sort where
  ann (Sort _ _ a) = a
  setAnn a (Sort i ss _) = Sort i ss a

instance Annotated QualIdentifier where
  ann = \case
    QIdentifier _ a     -> a
    QIdentifierAs _ _ a -> a
  setAnn a = \case
    QIdentifier i _     -> QIdentifier i a
    QIdentifierAs i s _ -> QIdentifierAs i s a
