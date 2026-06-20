{-# LANGUAGE OverloadedStrings #-}

-- | A small command-line front end: parse an SMT-LIB 2 script from a file (or
-- stdin) and re-emit it in canonical form, or report the parse error.
module Main (main) where

import qualified Data.Text.IO as T
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

import Language.SMTLIB

main :: IO ()
main = do
  args <- getArgs
  (name, src) <- case args of
    []     -> (,) "<stdin>" <$> T.getContents
    [f]    -> (,) f <$> T.readFile f
    _      -> hPutStrLn stderr "usage: language-smtlib-fmt [FILE]" >> exitFailure >> pure ("", "")
  case parseScript name src of
    Left err     -> hPutStrLn stderr (errorBundlePretty err) >> exitFailure
    Right script -> T.putStr (renderScript script)
