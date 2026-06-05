-- | The incremental S-expression framer: the low-level primitive that decides
-- where one complete top-level S-expression ends.
--
-- It scans 'Text' left-to-right tracking parenthesis depth, string literals,
-- @|...|@ quoted symbols and @;@ line comments, and classifies the input as one
-- of three outcomes ('Result'):
--
--   * 'Done' — a complete frame, with the unconsumed remainder of the chunk.
--   * 'Partial' — the input ends in the middle of a frame; feed more to
--     continue (this is the \"needs more input\" signal a REPL uses to prompt
--     for a continuation line).
--   * 'Failed' — a lexical framing error.
--
-- It performs /minimal reads/: it returns 'Done' the instant a frame closes and
-- hands back the remainder, so a pipe driver never consumes past one command.
-- It only asks for more input at genuine ambiguities (an open list, an open
-- string\/quoted symbol, or a trailing @\"@ that might begin a @\"\"@ escape).
--
-- The framer is deliberately permissive about /syntax/: it accepts any
-- balanced byte sequence and leaves rich syntactic error reporting to the
-- megaparsec layer that re-parses the framed text.
module Language.SMTLIB.Parser.SExpr
  ( Result(..)
  , FrameError(..)
  , feed
  , isCleanEnd
  , frameSExpr
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import Data.Text.Lazy.Builder (Builder)
import qualified Data.Text.Lazy.Builder as B

-- | The outcome of framing.  @a@ is the framed payload (raw 'Text' for
-- 'frameSExpr').
data Result a
  = Done a !Text                 -- ^ framed value and the unconsumed remainder
  | Partial (Text -> Result a)   -- ^ feed the next chunk; feed @""@ to signal EOF
  | Failed FrameError !Text       -- ^ framing error and the remaining input

-- | Map over the framed payload, threading through 'Partial' continuations.
-- This is how the framed 'Text' of a 'Done' is handed to the megaparsec layer.
instance Functor Result where
  fmap f (Done a t)  = Done (f a) t
  fmap f (Partial k) = Partial (fmap f . k)
  fmap _ (Failed e t) = Failed e t

-- | A framing-level error.  'EndOfInput' is benign: it reports that the stream
-- ended cleanly at a frame boundary with no partial frame in progress.
data FrameError
  = UnterminatedString        -- ^ EOF inside a @"..."@ literal
  | UnterminatedQuotedSymbol  -- ^ EOF inside a @|...|@ symbol
  | UnterminatedList          -- ^ EOF inside a @(...)@ with unmatched @(@
  | UnexpectedCloseParen      -- ^ a @)@ with no matching @(@
  | EndOfInput                -- ^ stream ended cleanly between frames (not an error)
  deriving (Eq, Show)

-- | Apply the next input chunk to a pending 'Partial'.  A non-'Partial' result
-- is returned unchanged.  Feed @""@ to signal end of input.
feed :: Result a -> Text -> Result a
feed (Partial k) t = k t
feed r           _ = r

-- | Whether a result is the benign end-of-stream marker (@'Failed' 'EndOfInput'@).
isCleanEnd :: Result a -> Bool
isCleanEnd (Failed EndOfInput _) = True
isCleanEnd _                     = False

-- | Frame exactly one top-level S-expression from the given input, returning
-- the raw 'Text' of the frame (verbatim, including any interior comments and
-- whitespace) on success.
frameSExpr :: Text -> Result Text
frameSExpr = skip False

-- The accumulator holds the frame characters consumed so far; leading layout
-- (whitespace and comments before the frame) is never accumulated.

-- | Whitespace recognised between tokens.
isWs :: Char -> Bool
isWs c = c == ' ' || c == '\t' || c == '\n' || c == '\r'

-- | Characters that terminate a bare top-level atom.
isDelim :: Char -> Bool
isDelim c = isWs c || c == '(' || c == ')' || c == '"' || c == '|' || c == ';'

toText :: Builder -> Text
toText = TL.toStrict . B.toLazyText

done :: Builder -> Text -> Result Text
done acc rest = Done (toText acc) rest

-- | Inner lexical mode while scanning the body of a list.
data Inner = INormal | IComment | IQuo | IStr | IStrQuote

-- | Skip leading whitespace and comments, then dispatch on the first
-- significant character.  The 'Bool' records whether we are currently inside a
-- leading line comment.
skip :: Bool -> Text -> Result Text
skip inComment t = case T.uncons t of
  Nothing -> Partial $ \more ->
    if T.null more then Failed EndOfInput T.empty else skip inComment more
  Just (c, rest)
    | inComment -> skip (not (c == '\n' || c == '\r')) rest
    | c == ';'  -> skip True rest
    | isWs c    -> skip False rest
    | c == '('  -> inList INormal 1 (B.singleton '(') rest
    | c == ')'  -> Failed UnexpectedCloseParen t
    | c == '"'  -> inStr (B.singleton '"') rest
    | c == '|'  -> inQuo (B.singleton '|') rest
    | otherwise -> inSimple (B.singleton c) rest

-- | A bare top-level atom, ending at the first delimiter or at EOF.
inSimple :: Builder -> Text -> Result Text
inSimple acc t = case T.uncons t of
  Nothing -> Partial $ \more ->
    if T.null more then done acc T.empty else inSimple acc more
  Just (c, _)
    | isDelim c -> done acc t                         -- delimiter not consumed
  Just (c, rest) -> inSimple (acc <> B.singleton c) rest

-- | A top-level @"..."@ string literal.
inStr :: Builder -> Text -> Result Text
inStr acc t = case T.uncons t of
  Nothing -> Partial $ \more ->
    if T.null more then Failed UnterminatedString T.empty else inStr acc more
  Just (c, rest)
    | c == '"'  -> inStrQuote (acc <> B.singleton '"') rest
    | otherwise -> inStr (acc <> B.singleton c) rest

-- | Just consumed a @"@ inside a top-level string; decide whether it closed the
-- string or begins a @""@ escape.
inStrQuote :: Builder -> Text -> Result Text
inStrQuote acc t = case T.uncons t of
  Nothing -> Partial $ \more ->
    if T.null more then done acc T.empty else inStrQuote acc more  -- EOF: string closed
  Just (c, rest)
    | c == '"'  -> inStr (acc <> B.singleton '"') rest             -- "" escape
    | otherwise -> done acc t                                      -- closed; c is remainder

-- | A top-level @|...|@ quoted symbol.
inQuo :: Builder -> Text -> Result Text
inQuo acc t = case T.uncons t of
  Nothing -> Partial $ \more ->
    if T.null more then Failed UnterminatedQuotedSymbol T.empty else inQuo acc more
  Just (c, rest)
    | c == '|'  -> done (acc <> B.singleton '|') rest
    | otherwise -> inQuo (acc <> B.singleton c) rest

-- | Inside a list at the given depth (>= 1).
inList :: Inner -> Int -> Builder -> Text -> Result Text
inList inner depth acc t = case T.uncons t of
  Nothing -> Partial $ \more ->
    if T.null more then Failed UnterminatedList T.empty
    else inList inner depth acc more
  Just (c, rest) -> case inner of
    INormal -> normalChar depth acc c rest
    IComment
      | c == '\n' || c == '\r' -> inList INormal depth (acc <> B.singleton c) rest
      | otherwise              -> inList IComment depth (acc <> B.singleton c) rest
    IQuo
      | c == '|'  -> inList INormal depth (acc <> B.singleton c) rest
      | otherwise -> inList IQuo depth (acc <> B.singleton c) rest
    IStr
      | c == '"'  -> inList IStrQuote depth (acc <> B.singleton c) rest
      | otherwise -> inList IStr depth (acc <> B.singleton c) rest
    IStrQuote
      | c == '"'  -> inList IStr depth (acc <> B.singleton c) rest   -- "" escape
      | otherwise -> normalChar depth acc c rest                     -- string closed

-- | Process one character in normal (non-string\/comment) list context.
normalChar :: Int -> Builder -> Char -> Text -> Result Text
normalChar depth acc c rest =
  let acc' = acc <> B.singleton c in
  case c of
    '(' -> inList INormal (depth + 1) acc' rest
    ')' | depth == 1 -> done acc' rest
        | otherwise  -> inList INormal (depth - 1) acc' rest
    '"' -> inList IStr depth acc' rest
    '|' -> inList IQuo depth acc' rest
    ';' -> inList IComment depth acc' rest
    _   -> inList INormal depth acc' rest
