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
  , module Language.SMTLIB.Parser.Response
  , module Language.SMTLIB.Printer
  , errorBundlePretty
  ) where

import Text.Megaparsec (errorBundlePretty)

import Language.SMTLIB.Parser
import Language.SMTLIB.Parser.Response
import Language.SMTLIB.Printer
import Language.SMTLIB.Syntax
