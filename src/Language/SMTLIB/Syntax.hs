-- | The full SMT-LIB 2 abstract syntax tree.
--
-- Every node type takes a final annotation type parameter @a@; use @()@ for a
-- plain tree or t'SrcSpan' for one decorated with source positions.  This module
-- re-exports all of the individual @Language.SMTLIB.Syntax.*@ modules.
module Language.SMTLIB.Syntax
  ( module Language.SMTLIB.Syntax.Annotation
  , module Language.SMTLIB.Syntax.Constant
  , module Language.SMTLIB.Syntax.Identifier
  , module Language.SMTLIB.Syntax.Attribute
  , module Language.SMTLIB.Syntax.Term
  , module Language.SMTLIB.Syntax.Datatype
  , module Language.SMTLIB.Syntax.Command
  , module Language.SMTLIB.Syntax.Response
  ) where

import Language.SMTLIB.Syntax.Annotation
import Language.SMTLIB.Syntax.Attribute
import Language.SMTLIB.Syntax.Command
import Language.SMTLIB.Syntax.Constant
import Language.SMTLIB.Syntax.Datatype
import Language.SMTLIB.Syntax.Identifier
import Language.SMTLIB.Syntax.Response
import Language.SMTLIB.Syntax.Term
