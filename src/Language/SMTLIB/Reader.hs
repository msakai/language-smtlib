-- | Pure helpers for the incremental S-expression reader.  Re-exports the
-- framer primitives and adds bulk\/whole-text conveniences built on top of them.
module Language.SMTLIB.Reader
  ( -- * Framer primitives (re-exported)
    Result(..)
  , FrameError(..)
  , feed
  , isCleanEnd
  , frameSExpr
    -- * Whole-text helpers
  , frameAll
  , frameOne
  ) where

import Data.Text (Text)

import Language.SMTLIB.Parser.SExpr

-- | Frame a single complete S-expression from @t@, signalling end-of-input so
-- that an incomplete frame becomes a 'FrameError' rather than a 'Partial'.
--
-- Returns @Right (Just (frame, remainder))@ on success, @Right Nothing@ if @t@
-- holds only whitespace\/comments, or @Left err@ on an incomplete or invalid
-- frame.
frameOne :: Text -> Either FrameError (Maybe (Text, Text))
frameOne t = case feed (frameSExpr t) "" of
  Done f rest        -> Right (Just (f, rest))
  Failed EndOfInput _ -> Right Nothing
  Failed e _         -> Left e
  Partial _          -> Right Nothing  -- unreachable: EOF resolves every Partial

-- | Split a complete input into its top-level S-expression frames.  The second
-- component is 'Just' an error when the trailing input is an incomplete or
-- malformed frame (the successfully framed prefix is still returned).
frameAll :: Text -> ([Text], Maybe FrameError)
frameAll = go []
  where
    go acc t = case feed (frameSExpr t) "" of
      Done f rest         -> go (f : acc) rest
      Failed EndOfInput _ -> (reverse acc, Nothing)
      Failed e _          -> (reverse acc, Just e)
      Partial _           -> (reverse acc, Nothing)  -- unreachable after EOF
