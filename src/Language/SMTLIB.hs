-- | Top-level entry point for the SMT-LIB 2 library: the AST, the parser
-- (whole-text and incremental) and the printer.
--
-- @
-- import qualified Data.Text.IO as T
-- import Language.SMTLIB
--
-- main = do
--   src <- T.readFile \"problem.smt2\"
--   case parseScript \"problem.smt2\" src of
--     Left err     -> putStr (errorBundlePretty err)
--     Right script -> T.putStr (renderScript script)
-- @
module Language.SMTLIB
  ( module Language.SMTLIB.Syntax
  , module Language.SMTLIB.Parser
  , module Language.SMTLIB.Printer
    -- * Error rendering (re-exported from megaparsec)

    -- | Render a megaparsec error bundle (as returned by 'parseScript' and
    -- friends) into a human-readable, multi-line string.
  , errorBundlePretty
  ) where

import Text.Megaparsec (errorBundlePretty)

import Language.SMTLIB.Parser
import Language.SMTLIB.Printer
import Language.SMTLIB.Syntax
