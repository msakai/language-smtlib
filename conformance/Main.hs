{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns #-}

-- | A conformance / stress-test driver for large external SMT-LIB 2 benchmark
-- suites (such as the SMT-LIB / SMT-COMP collections published on Zenodo).
--
-- It walks one or more files or directories, finds every @.smt2@ file, and for
-- each one verifies the library's full round-trip guarantee:
--
--   * read every command (streaming, one command at a time, so arbitrarily
--     large files use bounded memory);
--   * re-render each command with 'renderText';
--   * re-parse the rendered text with 'parseCommand'';
--   * check that the re-parsed AST equals the original (modulo source spans).
--
-- Failures are classified (parse / re-parse / AST mismatch / I\/O) and a summary
-- is printed at the end.  The process exits non-zero if any file failed.
--
-- This tool is intentionally /not/ part of the normal build or test suite: the
-- benchmark data is huge and lives outside the repository.  It is only built
-- when the @tools@ cabal flag is set, e.g.
--
-- @
-- stack build --flag language-smtlib:tools
-- stack exec language-smtlib-conformance -- benchmarks\/
-- @
module Main (main) where

import Control.Exception (SomeException, try)
import Control.Monad (foldM, forM, when)
import Data.IORef
import Data.List (sort)
import qualified Data.Text as T
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.Environment (getArgs, getProgName)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath (takeExtension, (</>))
import System.IO

import Language.SMTLIB
import Language.SMTLIB.Reader.Handle (newHandleReader, readCommand)

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------

data Options = Options
  { optLimit        :: !(Maybe Int)  -- ^ process at most this many files
  , optQuiet        :: !Bool         -- ^ suppress per-failure lines (summary only)
  , optShowFailures :: !Int          -- ^ cap on per-failure lines printed
  , optPaths        :: ![FilePath]   -- ^ files or directories to scan
  }

defaultOptions :: Options
defaultOptions = Options
  { optLimit        = Nothing
  , optQuiet        = False
  , optShowFailures = 20
  , optPaths        = []
  }

parseArgs :: [String] -> Either String Options
parseArgs = go defaultOptions
  where
    go opts [] = Right opts { optPaths = reverse (optPaths opts) }
    go opts (a : rest) = case a of
      "--limit" -> case rest of
        (n : rest') -> withInt n (\k -> go opts { optLimit = Just k } rest')
        []          -> Left "--limit requires an argument"
      "--show-failures" -> case rest of
        (n : rest') -> withInt n (\k -> go opts { optShowFailures = k } rest')
        []          -> Left "--show-failures requires an argument"
      "--quiet" -> go opts { optQuiet = True } rest
      _ | take 2 a == "--" -> Left ("unknown option: " ++ a)
        | otherwise        -> go opts { optPaths = a : optPaths opts } rest

    withInt s k = case reads s of
      [(n, "")] -> k n
      _         -> Left ("expected an integer, got: " ++ s)

usage :: String -> String
usage prog = unlines
  [ "usage: " ++ prog ++ " [OPTIONS] PATH..."
  , ""
  , "Round-trip (parse -> render -> re-parse) every .smt2 file under each PATH."
  , "A PATH may be a single file or a directory (scanned recursively)."
  , ""
  , "Options:"
  , "  --limit N           process at most N files"
  , "  --show-failures N   print at most N failure detail lines (default 20)"
  , "  --quiet             only print the final summary"
  , "  -h, --help          show this help"
  ]

-- ---------------------------------------------------------------------------
-- Per-file checking
-- ---------------------------------------------------------------------------

data FailKind = ParseFail | ReparseFail | MismatchFail | IOFail
  deriving (Eq, Ord, Show)

kindLabel :: FailKind -> String
kindLabel ParseFail    = "parse"
kindLabel ReparseFail  = "reparse"
kindLabel MismatchFail = "mismatch"
kindLabel IOFail       = "io"

data Failure = Failure
  { fKind :: !FailKind
  , fMsg  :: !String
  }

data Outcome = Outcome
  { oCommands :: !Int            -- ^ commands successfully read
  , oFailure  :: !(Maybe Failure)
  }

-- | Stream a single file command-by-command, round-tripping each command.
-- Stops at the first failure (a framing error makes the rest unreliable, and
-- one report per file keeps the output manageable).
checkFile :: FilePath -> IO Outcome
checkFile path = do
  res <- try (withFile path ReadMode run) :: IO (Either SomeException Outcome)
  pure $ case res of
    Left e  -> Outcome 0 (Just (Failure IOFail (show e)))
    Right o -> o
  where
    run h = do
      hSetEncoding h utf8
      hr <- newHandleReader h
      let loop !n = do
            r <- readCommand hr
            case r of
              Left err       -> pure (Outcome n (Just (Failure ParseFail err)))
              Right Nothing  -> pure (Outcome n Nothing)
              Right (Just c) ->
                let rendered = renderText c
                in case parseCommand' "<rerender>" rendered of
                     Left e -> pure (Outcome (n + 1)
                                 (Just (Failure ReparseFail (errorBundlePretty e))))
                     Right c'
                       | noAnn c == c' -> loop (n + 1)
                       | otherwise     -> pure (Outcome (n + 1)
                           (Just (Failure MismatchFail
                             ("AST changed after render/re-parse; rendered: "
                               ++ truncateStr 200 (T.unpack rendered)))))
      loop 0

-- ---------------------------------------------------------------------------
-- File discovery
-- ---------------------------------------------------------------------------

-- | Collect @.smt2@ files.  An explicitly named file is taken as-is regardless
-- of extension; directories are recursed and filtered to @.smt2@.
gather :: FilePath -> IO [FilePath]
gather p = do
  isDir <- doesDirectoryExist p
  if isDir
    then collectDir p
    else do
      isFile <- doesFileExist p
      if isFile
        then pure [p]
        else do
          hPutStrLn stderr ("warning: path not found, skipping: " ++ p)
          pure []

collectDir :: FilePath -> IO [FilePath]
collectDir d = do
  entries <- listDirectory d
  fmap concat $ forM (sort entries) $ \e -> do
    let p = d </> e
    isDir <- doesDirectoryExist p
    if isDir
      then collectDir p
      else pure [p | takeExtension p == ".smt2"]

-- ---------------------------------------------------------------------------
-- Driver
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  args <- getArgs
  prog <- getProgName
  if any (`elem` ["-h", "--help"]) args
    then putStr (usage prog) >> exitSuccess
    else pure ()
  opts <- case parseArgs args of
    Left err -> hPutStrLn stderr (err ++ "\n") >> hPutStr stderr (usage prog) >> exitFailure
    Right o  -> pure o
  when (null (optPaths opts)) $ do
    hPutStrLn stderr "error: no paths given\n"
    hPutStr stderr (usage prog)
    exitFailure

  files0 <- concat <$> mapM gather (optPaths opts)
  let files = maybe id take (optLimit opts) files0
  putStrLn ("Found " ++ show (length files) ++ " .smt2 file(s) to check.")

  -- Counters.
  cmdTotal   <- newIORef (0 :: Integer)
  failParse  <- newIORef (0 :: Int)
  failRepars <- newIORef (0 :: Int)
  failMismat <- newIORef (0 :: Int)
  failIO     <- newIORef (0 :: Int)
  printed    <- newIORef (0 :: Int)

  let bump ref = modifyIORef' ref (+ 1)
      bumpKind ParseFail    = bump failParse
      bumpKind ReparseFail  = bump failRepars
      bumpKind MismatchFail = bump failMismat
      bumpKind IOFail       = bump failIO

  okCount <- foldM
    (\ !ok path -> do
        o <- checkFile path
        modifyIORef' cmdTotal (+ fromIntegral (oCommands o))
        case oFailure o of
          Nothing -> pure (ok + 1 :: Int)
          Just f  -> do
            bumpKind (fKind f)
            n <- readIORef printed
            when (not (optQuiet opts) && n < optShowFailures opts) $ do
              writeIORef printed (n + 1)
              putStrLn ("FAIL [" ++ kindLabel (fKind f) ++ "] " ++ path
                          ++ ": " ++ firstLine (fMsg f))
            pure ok)
    0
    files

  -- Summary.
  cmds <- readIORef cmdTotal
  fp <- readIORef failParse
  fr <- readIORef failRepars
  fm <- readIORef failMismat
  fi <- readIORef failIO
  let total   = length files
      failed  = fp + fr + fm + fi
  putStrLn ""
  putStrLn "==== Summary ===="
  putStrLn ("files checked : " ++ show total)
  putStrLn ("  passed      : " ++ show okCount)
  putStrLn ("  failed      : " ++ show failed)
  putStrLn ("commands read : " ++ show cmds)
  when (failed > 0) $ do
    putStrLn "failures by kind:"
    putStrLn ("  parse    : " ++ show fp)
    putStrLn ("  reparse  : " ++ show fr)
    putStrLn ("  mismatch : " ++ show fm)
    putStrLn ("  io       : " ++ show fi)
  if failed > 0 then exitFailure else exitSuccess

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

firstLine :: String -> String
firstLine = truncateStr 300 . takeWhile (/= '\n')

truncateStr :: Int -> String -> String
truncateStr n s =
  let (h, t) = splitAt n s
  in if null t then h else h ++ "..."
