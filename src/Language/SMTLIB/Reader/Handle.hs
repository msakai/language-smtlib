-- | Reading S-expressions and commands incrementally from a 'Handle' (a file, a
-- socket, or a pipe to a running solver).
--
-- A t'HandleReader' buffers any input read past the end of one frame, so the
-- next read resumes from it.  Crucially, it reads from the handle /only/ while a
-- frame is still incomplete: once a frame closes it returns immediately without
-- touching the handle, so it never blocks waiting for input beyond the command
-- it has already received.  Reads use 'T.hGetChunk', which returns whatever is
-- currently available rather than waiting to fill a buffer.
--
-- This module deliberately does not manage solver subprocesses; it provides the
-- reading primitive that such a driver builds on.
module Language.SMTLIB.Reader.Handle
  ( HandleReader
  , newHandleReader
  , readSExpr
  , readCommand
  ) where

import Data.IORef
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.IO (Handle)
import Text.Megaparsec (eof, errorBundlePretty, parse)

import Language.SMTLIB.Parser.Command (pCommand)
import Language.SMTLIB.Parser.Internal (sc)
import Language.SMTLIB.Parser.SExpr
import Language.SMTLIB.Syntax.Annotation (SrcSpan)
import Language.SMTLIB.Syntax.Command (Command)

-- | A handle paired with a buffer of input read past the previous frame.
data HandleReader = HandleReader
  { hrHandle   :: !Handle
  , hrLeftover :: !(IORef Text)
  }

-- | Create a reader over a handle.
newHandleReader :: Handle -> IO HandleReader
newHandleReader h = HandleReader h <$> newIORef T.empty

-- | Read the next complete top-level S-expression as raw 'Text'.
--
--   * @'Right' ('Just' frame)@ — a complete frame;
--   * @'Right' 'Nothing'@ — the stream ended cleanly with no further frame;
--   * @'Left' err@ — a framing error (e.g. unbalanced parentheses, EOF inside a
--     string).
readSExpr :: HandleReader -> IO (Either FrameError (Maybe Text))
readSExpr hr = do
  leftover <- readIORef (hrLeftover hr)
  drive (frameSExpr leftover)
  where
    drive (Done frame rest) = do
      writeIORef (hrLeftover hr) rest
      pure (Right (Just frame))
    drive (Failed EndOfInput _) = pure (Right Nothing)
    drive (Failed e _)          = pure (Left e)
    drive (Partial k)           = do
      chunk <- T.hGetChunk (hrHandle hr)  -- "" at EOF; never reads more than available
      drive (k chunk)

-- | Read and parse the next complete command.  Returns @Right Nothing@ at a
-- clean end of stream, @Left msg@ on a framing or syntax error.
readCommand :: HandleReader -> IO (Either String (Maybe (Command SrcSpan)))
readCommand hr = do
  r <- readSExpr hr
  pure $ case r of
    Left fe          -> Left ("framing error: " ++ show fe)
    Right Nothing    -> Right Nothing
    Right (Just txt) -> case parse (sc *> pCommand <* eof) "<handle>" txt of
      Left e  -> Left (errorBundlePretty e)
      Right c -> Right (Just c)
