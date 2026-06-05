-- | Source-location machinery for the (optionally) annotated SMT-LIB AST.
--
-- Every AST node carries a final type parameter @a@ that holds an annotation.
-- Use @()@ for a plain, location-free tree and 'SrcSpan' for a tree decorated
-- with source positions.  Because the annotation always sits in the last field
-- of every constructor, the AST types derive 'Functor'/'Foldable'/'Traversable'
-- over @a@, so 'noAnn' (= 'void') erases all annotations uniformly.
module Language.SMTLIB.Syntax.Annotation
  ( SrcSpan(..)
  , Annotated(..)
  , noAnn
  ) where

import Data.Functor (void)

-- | A half-open span @[spanStart, spanEnd)@ in the source text, measured in
-- 0-based character offsets.  Offsets (rather than line\/column pairs) keep span
-- capture O(1) per node; line and column can be recovered on demand from the
-- original source.
data SrcSpan = SrcSpan
  { spanStart :: !Int
  , spanEnd   :: !Int
  } deriving (Eq, Ord, Show)

-- | Access or replace the top-level annotation of a node.
--
-- Unlike 'Foldable', which would collect the annotations of /every/ sub-node,
-- 'ann' returns only the annotation attached to the outermost constructor.
class Annotated f where
  ann    :: f a -> a
  setAnn :: a -> f a -> f a

-- | Erase all annotations, turning any annotated tree into a plain @()@ tree.
noAnn :: Functor f => f a -> f ()
noAnn = void
