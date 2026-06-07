{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (filterM, forM)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>), takeExtension)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import Text.Megaparsec (eof, errorBundlePretty, parse)

import Arbitrary ()
import Language.SMTLIB
import Language.SMTLIB.Parser.Command
import Language.SMTLIB.Parser.Internal
import Language.SMTLIB.Parser.SExpr
import Language.SMTLIB.Parser.Term
import Language.SMTLIB.Reader (frameAll)

main :: IO ()
main = do
  sampleTests <- loadSampleTests
  defaultMain $ testGroup "language-smtlib"
    [ roundTripTests
    , framerTests
    , streamingTests
    , sampleTests
    ]

-- Round-trip: parse . render == id (modulo annotations) ----------------------

roundTrip
  :: (Eq (f ()), Show (f ()), Functor f, Pretty (f ()))
  => P (f SrcSpan) -> f () -> Property
roundTrip p x =
  let txt = renderText x
  in case parse (sc *> p <* eof) "<rt>" txt of
       Left e  -> counterexample (T.unpack txt ++ "\n" ++ errorBundlePretty e) (property False)
       Right y -> counterexample (T.unpack txt) (noAnn y === x)

roundTripTests :: TestTree
roundTripTests = testGroup "round-trip (parse . render == id)"
  [ testProperty "SpecConstant"   (roundTrip pSpecConstant   :: SpecConstant () -> Property)
  , testProperty "Index"          (roundTrip pIndex          :: Index () -> Property)
  , testProperty "Identifier"     (roundTrip pIdentifier     :: Identifier () -> Property)
  , testProperty "Sort"           (roundTrip pSort           :: Sort () -> Property)
  , testProperty "QualIdentifier" (roundTrip pQualIdentifier :: QualIdentifier () -> Property)
  , testProperty "SExpr"          (roundTrip pSExpr          :: SExpr () -> Property)
  , testProperty "AttributeValue" (roundTrip pAttributeValue :: AttributeValue () -> Property)
  , testProperty "Attribute"      (roundTrip pAttribute      :: Attribute () -> Property)
  , testProperty "VarBinding"     (roundTrip pVarBinding     :: VarBinding () -> Property)
  , testProperty "SortedVar"      (roundTrip pSortedVar      :: SortedVar () -> Property)
  , testProperty "Pattern"        (roundTrip pPattern        :: Pattern () -> Property)
  , testProperty "MatchCase"      (roundTrip pMatchCase      :: MatchCase () -> Property)
  , testProperty "Term"           (roundTrip pTerm           :: Term () -> Property)
  , testProperty "SortDec"        (roundTrip pSortDec        :: SortDec () -> Property)
  , testProperty "SelectorDec"    (roundTrip pSelectorDec    :: SelectorDec () -> Property)
  , testProperty "ConstructorDec" (roundTrip pConstructorDec :: ConstructorDec () -> Property)
  , testProperty "DatatypeDec"    (roundTrip pDatatypeDec    :: DatatypeDec () -> Property)
  , testProperty "FunctionDec"    (roundTrip pFunctionDec    :: FunctionDec () -> Property)
  , testProperty "FunctionDef"    (roundTrip pFunctionDef    :: FunctionDef () -> Property)
  , testProperty "Option"         (roundTrip pOption         :: Option () -> Property)
  , testProperty "InfoFlag"       (roundTrip pInfoFlag       :: InfoFlag () -> Property)
  , testProperty "Command"        (roundTrip pCommand        :: Command () -> Property)
  ]

-- Framer ---------------------------------------------------------------------

data Outcome = ODone Text Text | OPartial | OFailed FrameError Text
  deriving (Eq, Show)

toOutcome :: Result Text -> Outcome
toOutcome (Done a r)   = ODone a r
toOutcome (Partial _)  = OPartial
toOutcome (Failed e r) = OFailed e r

-- | Feed all of @t@ then signal EOF.
runEOF :: Text -> Outcome
runEOF t = toOutcome (feed (frameSExpr t) "")

-- | Frame @t@ without signalling EOF (REPL view).
runNoEOF :: Text -> Outcome
runNoEOF = toOutcome . frameSExpr

-- | Feed the input one character at a time (no EOF).
feedByChar :: Text -> Outcome
feedByChar = toOutcome . T.foldl' (\r c -> feed r (T.singleton c)) (frameSExpr "")

framerTests :: TestTree
framerTests = testGroup "S-expression framer"
  [ testCase "complete list" $ runEOF "(check-sat)" @?= ODone "(check-sat)" ""
  , testCase "incomplete list is Partial" $ runNoEOF "(assert (= a" @?= OPartial
  , testCase "unexpected close paren" $ runNoEOF ")" @?= OFailed UnexpectedCloseParen ")"
  , testCase "unterminated string" $ runEOF "\"ab" @?= OFailed UnterminatedString ""
  , testCase "unterminated quoted symbol" $ runEOF "|abc" @?= OFailed UnterminatedQuotedSymbol ""
  , testCase "top-level atom at EOF" $ runEOF "sat" @?= ODone "sat" ""
  , testCase "top-level atom at delimiter" $ runNoEOF "sat " @?= ODone "sat" " "
  , testCase "atom alone is Partial without EOF" $ runNoEOF "sat" @?= OPartial
  , testCase "clean EOF on empty input" $ runEOF "" @?= OFailed EndOfInput ""
  , testCase "clean EOF on whitespace" $ runEOF "  \n " @?= OFailed EndOfInput ""
  , testCase "minimal read keeps remainder" $ runNoEOF "(a)(b)" @?= ODone "(a)" "(b)"
  , testCase "paren inside comment ignored" $
      runEOF "(a ; ) cmt\n b)" @?= ODone "(a ; ) cmt\n b)" ""
  , testCase "paren inside string ignored" $
      runEOF "(echo \")\")" @?= ODone "(echo \")\")" ""
  , testCase "escaped quote inside string" $
      runEOF "(echo \"a\"\"b\")" @?= ODone "(echo \"a\"\"b\")" ""
  , testCase "char-by-char: Done only at boundary" $
      feedByChar "(a b)" @?= ODone "(a b)" ""
  , testCase "char-by-char: Partial before boundary" $
      feedByChar "(a b" @?= OPartial
  , testCase "leading comment skipped" $
      runEOF "; hello\n(exit)" @?= ODone "(exit)" ""
  ]

-- Streaming / framer-vs-parser equivalence -----------------------------------

streamingTests :: TestTree
streamingTests = testGroup "streaming"
  [ testProperty "frameAll count matches command count" propFrameCount
  , testProperty "frame-then-parse == direct parse" propFrameEqualsDirect
  ]

propFrameCount :: [Command ()] -> Property
propFrameCount cmds =
  let txt = renderScript cmds
      (frames, merr) = frameAll txt
  in counterexample (T.unpack txt) $
       (merr === Nothing) .&&. (length frames === length cmds)

propFrameEqualsDirect :: [Command ()] -> Property
propFrameEqualsDirect cmds =
  let txt = renderScript cmds
      direct = fmap (map noAnn) (parseScript "<s>" txt)
      (frames, _) = frameAll txt
      perFrame = traverse (\f -> noAnn <$> parse (sc *> pCommand <* eof) "<f>" f) frames
  in counterexample (T.unpack txt) $
       (direct == Right cmds) .&&. either (const False) (== cmds) perFrame

-- Sample files ---------------------------------------------------------------

loadSampleTests :: IO TestTree
loadSampleTests = do
  let dir = "test" </> "samples" </> "smt"
  exists <- doesDirectoryExist dir
  if not exists
    then pure (testGroup "samples (skipped: directory not found)" [])
    else do
      entries <- listDirectory dir
      let smt2 = [ dir </> e | e <- entries, takeExtension e == ".smt2" ]
      files <- filterM doesFileExist smt2
      cases <- forM files $ \f -> do
        src <- T.readFile f
        pure (testCase f (assertParsesAndRoundTrips src))
      pure (testGroup "samples (parse + render idempotence)" cases)

assertParsesAndRoundTrips :: Text -> Assertion
assertParsesAndRoundTrips src =
  case parseScript "sample" src of
    Left e   -> assertFailure ("parse failed:\n" ++ errorBundlePretty e)
    Right s1 ->
      case parseScript "sample (rerender)" (renderScript s1) of
        Left e   -> assertFailure ("re-parse failed:\n" ++ errorBundlePretty e)
        Right s2 -> map noAnn s1 @?= map noAnn s2
