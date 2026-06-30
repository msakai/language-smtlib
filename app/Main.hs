{-# LANGUAGE OverloadedStrings #-}

-- | A small command-line front end: parse an SMT-LIB 2 script from a file (or
-- stdin) and re-emit it in canonical form, or report the parse error.
module Main (main) where

import qualified Data.Text.IO as T
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

import Language.SMTLIB
import Language.SMTLIB.Parser.Command (pScriptLenient)

main :: IO ()
main = do
  args <- getArgs
  case parseArgs args of
    Left msg -> hPutStrLn stderr msg >> exitFailure
    Right (lenient, mpath) -> do
      (name, src) <- case mpath of
        Nothing -> (,) "<stdin>" <$> T.getContents
        Just f  -> (,) f <$> T.readFile f
      let parse = if lenient then parseWith pScriptLenient else parseScript
      case parse name src of
        Left err     -> hPutStrLn stderr (errorBundlePretty err) >> exitFailure
        Right script -> T.putStr (renderScript script)

-- | Parse the command line into @(lenient, optional path)@.  @--lenient@ keeps
-- unrecognized commands as @UnknownCommand@ instead of failing the parse.
parseArgs :: [String] -> Either String (Bool, Maybe FilePath)
parseArgs = go False Nothing
  where
    go lenient mpath args = case args of
      []                  -> Right (lenient, mpath)
      ("--lenient" : rest) -> go True mpath rest
      (a : rest)
        | take 1 a == "-"  -> Left ("unknown option: " ++ a ++ "\n" ++ usage)
        | otherwise        -> case mpath of
            Nothing -> go lenient (Just a) rest
            Just _  -> Left ("too many file arguments\n" ++ usage)

usage :: String
usage = "usage: language-smtlib-fmt [--lenient] [FILE]"
