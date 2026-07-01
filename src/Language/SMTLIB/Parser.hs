-- | The public parsing API.
--
-- Two entry styles are offered:
--
--   * Whole-text parsing ('parseScript', 'parseCommand', 'parseTerm') runs
--     megaparsec over the entire input and yields its rich
--     @ParseErrorBundle@ on failure.
--
--   * Incremental parsing ('frameCommand') runs the S-expression framer first,
--     so it can distinguish \"needs more input\" ('Partial') from a real
--     framing error, and only invokes megaparsec on a complete frame.  This is
--     the entry point for REPL\/pipe drivers.
--
-- The whole-text entry points are /strict/: an unrecognized command is a parse
-- error.  For lenient parsing — keeping an unknown command as
-- 'Language.SMTLIB.Syntax.Command.UnknownCommand' for the application to handle
-- — run the lenient parsers from "Language.SMTLIB.Parser.Command" through
-- 'parseWith', e.g. @'parseWith' 'Language.SMTLIB.Parser.Command.pScriptLenient'@.
-- Solver-response parsing
-- ("Language.SMTLIB.Parser.Response") is always lenient: an unrecognized
-- response is kept as 'Language.SMTLIB.Syntax.Response.ROther'.
module Language.SMTLIB.Parser
  ( -- * Parser monad
    P
    -- * Errors
  , MPError
  , ParseError(..)
  , prettyParseError
    -- * Whole-text parsing
  , parseScript
  , parseCommand
  , parseTerm
  , parseWith
    -- * Whole-text parsing (plain, location-free trees)
  , parseScript'
  , parseCommand'
  , parseTerm'
    -- * Incremental parsing
  , frameCommand
    -- * Re-exports from the framer
  , Result(..)
  , FrameError(..)
  , feed
  , isCleanEnd
  , frameSExpr
    -- * Command combinators
    -- | The lower-level command parsers, including the lenient variants
    -- ('pScriptLenient' \/ 'pCommandLenient') that keep an unrecognized command
    -- as 'Language.SMTLIB.Syntax.Command.UnknownCommand'.  Run them through
    -- 'parseWith'.
  , module Language.SMTLIB.Parser.Command
    -- * Response combinators
    -- | The solver-response parsers.  These have no whole-text wrapper of their
    -- own; run them through 'parseWith'.
  , module Language.SMTLIB.Parser.Response
  ) where

import Data.Text (Text)
import Data.Void (Void)
import Text.Megaparsec hiding (ParseError)

import Language.SMTLIB.Parser.Command
import Language.SMTLIB.Parser.Internal (P, sc)
import Language.SMTLIB.Parser.Response
import Language.SMTLIB.Parser.SExpr
import Language.SMTLIB.Parser.Term (pTerm)
import Language.SMTLIB.Syntax.Annotation (SrcSpan, noAnn)
import Language.SMTLIB.Syntax.Command (Command, Script)
import Language.SMTLIB.Syntax.Term (Term)

-- | The megaparsec error bundle produced for syntactic errors.
type MPError = ParseErrorBundle Text Void

-- | A unified parse error: either the framer rejected the input, or megaparsec
-- found a syntax error within a complete frame.
data ParseError
  = FramingError FrameError
  | SyntaxError MPError
  deriving (Show)

-- | Render a 'ParseError' for human consumption.
prettyParseError :: ParseError -> String
prettyParseError (FramingError e) = "framing error: " ++ show e
prettyParseError (SyntaxError e)  = errorBundlePretty e

runWhole :: P a -> FilePath -> Text -> Either MPError a
runWhole p = runParser (sc *> p <* eof)

-- | Parse a whole script (zero or more commands).
parseScript :: FilePath -> Text -> Either MPError (Script SrcSpan)
parseScript = runWhole pScript

-- | Parse a single command.
parseCommand :: FilePath -> Text -> Either MPError (Command SrcSpan)
parseCommand = runWhole pCommand

-- | Parse a single term.
parseTerm :: FilePath -> Text -> Either MPError (Term SrcSpan)
parseTerm = runWhole pTerm

-- | Run any parser (e.g. a response parser from
-- "Language.SMTLIB.Parser.Response") over a whole input, requiring it to
-- consume everything.  Leading whitespace is skipped automatically.
parseWith :: P a -> FilePath -> Text -> Either MPError a
parseWith p = runWhole p

-- | Like 'parseScript' but discarding source spans.
parseScript' :: FilePath -> Text -> Either MPError (Script ())
parseScript' fp = fmap (map noAnn) . parseScript fp

-- | Like 'parseCommand' but discarding source spans.
parseCommand' :: FilePath -> Text -> Either MPError (Command ())
parseCommand' fp = fmap noAnn . parseCommand fp

-- | Like 'parseTerm' but discarding source spans.
parseTerm' :: FilePath -> Text -> Either MPError (Term ())
parseTerm' fp = fmap noAnn . parseTerm fp

-- | Incrementally frame and parse one command.
--
-- The framer decides the boundary, so the result is:
--
--   * @'Done' ('Right' cmd) rest@ — a command parsed, with the remaining input;
--   * @'Done' ('Left' err) rest@ — a complete frame that failed to parse;
--   * @'Partial' k@ — the input ends mid-command; feed more (a REPL would
--     prompt for a continuation line);
--   * @'Failed' fe rest@ — a framing error (or @EndOfInput@ at a clean end).
frameCommand :: Text -> Result (Either MPError (Command SrcSpan))
frameCommand = fmap (runParser (sc *> pCommand <* eof) "<input>") . frameSExpr
