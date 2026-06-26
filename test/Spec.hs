{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (filterM, forM)
import Data.Either (isLeft)
import Data.Hashable (Hashable, hash)
import qualified Data.HashMap.Strict as HM
import Data.List (nub)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>), takeExtension)
import System.IO (IOMode (ReadMode), hSetEncoding, utf8, withFile)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import Text.Megaparsec (eof, errorBundlePretty, parse)

import Arbitrary ()
import Language.SMTLIB
import Language.SMTLIB.Parser.Command
import Language.SMTLIB.Parser.Internal
import Language.SMTLIB.Parser.Response (pCommandResponse)
import Language.SMTLIB.Parser.SExpr
import Language.SMTLIB.Parser.Term
import Language.SMTLIB.Reader (frameAll)

main :: IO ()
main = do
  sampleTests <- loadSampleTests
  defaultMain $ testGroup "language-smtlib"
    [ roundTripTests
    , leniencyTests
    , framerTests
    , streamingTests
    , instancesTests
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

-- Leniency: unknown commands / responses -------------------------------------

-- | A 'Command' built from an unrecognized head keyword, for exercising the
-- lenient parser's round-trip.  The head is a simple word guaranteed not to be
-- one of the recognized commands.
newtype UnknownCmd = UnknownCmd (Command ()) deriving Show

instance Arbitrary UnknownCmd where
  arbitrary = do
    kw   <- genUnknownHead
    args <- resize 3 (listOf (resize 3 arbitrary))
    pure (UnknownCmd (UnknownCommand kw args ()))

genUnknownHead :: Gen Text
genUnknownHead = (T.pack <$> word) `suchThat` (`notElem` knownCommandWords)
  where
    word = (:) <$> elements ['a'..'z']
               <*> resize 6 (listOf (elements (['a'..'z'] ++ "-")))

knownCommandWords :: [Text]
knownCommandWords =
  [ "set-logic", "set-option", "set-info", "declare-sort-parameter"
  , "declare-sort", "declare-const", "define-const", "declare-datatypes"
  , "declare-datatype", "declare-fun", "define-sort", "define-fun-rec"
  , "define-funs-rec", "define-fun", "push", "pop", "reset-assertions"
  , "reset", "assert", "check-sat-assuming", "check-sat", "get-assertions"
  , "get-assignment", "get-info", "get-model", "get-option", "get-proof"
  , "get-unsat-assumptions", "get-unsat-core", "get-value", "echo", "exit"
  ]

leniencyTests :: TestTree
leniencyTests = testGroup "leniency (unknown commands / responses)"
  [ testProperty "UnknownCommand round-trips via pCommandLenient" $
      \(UnknownCmd c) -> roundTrip pCommandLenient c
  , testCase "strict pCommand rejects an unknown head keyword" $
      assertBool "expected a parse failure" $
        isLeft (parse (sc *> pCommand <* eof) "<l>" "(frobnicate 1 2)")
  , testCase "lenient pCommand keeps an unknown head keyword" $
      case parse (sc *> pCommandLenient <* eof) "<l>" "(frobnicate 1 2)" of
        Right (UnknownCommand kw args _) -> do
          kw @?= "frobnicate"
          length args @?= 2
        _ -> assertFailure "expected UnknownCommand"
  , testCase "lenient pCommand still rejects a malformed known command" $
      assertBool "expected a parse failure" $
        isLeft (parse (sc *> pCommandLenient <* eof) "<l>" "(assert)")
  , testCase "unknown response falls back to ROther" $
      case parse (sc *> pCommandResponse <* eof) "<l>" "(custom-response 1 2)" of
        Right (ROther _) -> pure ()
        _ -> assertFailure "expected ROther"
  , testCase "known responses are still recognized" $
      case parse (sc *> pCommandResponse <* eof) "<l>" "success" of
        Right RSuccess -> pure ()
        _ -> assertFailure "expected RSuccess"
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

-- Ord / Hashable instances ---------------------------------------------------

instancesTests :: TestTree
instancesTests = testGroup "Ord / Hashable instances"
  [ testProperty "Eq agrees with Ord (Term)"       (propEqOrd :: Term () -> Term () -> Property)
  , testProperty "Eq agrees with Ord (Command)"    (propEqOrd :: Command () -> Command () -> Property)
  , testProperty "Eq implies equal hash (Term)"    (propEqHash :: Term () -> Property)
  , testProperty "Eq implies equal hash (Command)" (propEqHash :: Command () -> Property)
  , testProperty "usable as Map key (Term)"        (propMapKey :: [Term ()] -> Property)
  , testProperty "usable as HashMap key (Command)" (propHashMapKey :: [Command ()] -> Property)
  ]

-- | The derived 'Ord' must be consistent with the derived 'Eq'.
propEqOrd :: (Eq a, Ord a) => a -> a -> Property
propEqOrd x y = (x == y) === (compare x y == EQ)

-- | Structurally-equal values (here, a value against itself) hash equally;
-- this is the law every 'Hashable' instance must satisfy.
propEqHash :: Hashable a => a -> Property
propEqHash x = hash x === hash x

-- | A consistent 'Ord' lets values act as 'Data.Map' keys: a map keyed by a
-- list has exactly as many entries as the list has distinct elements.
propMapKey :: Ord a => [a] -> Property
propMapKey xs = M.size (M.fromList [(x, ()) | x <- xs]) === length (nub xs)

-- | Likewise for 'Data.HashMap' via the 'Hashable'\/'Eq' instances.
propHashMapKey :: (Eq a, Hashable a) => [a] -> Property
propHashMapKey xs = HM.size (HM.fromList [(x, ()) | x <- xs]) === length (nub xs)

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
        src <- readFileUtf8 f
        pure (testCase f (assertParsesAndRoundTrips src))
      pure (testGroup "samples (parse + render idempotence)" cases)

-- | Read a file as UTF-8, independent of the process's locale encoding.
-- (Sample files contain non-ASCII symbols, so the default locale-based
-- 'T.readFile' would fail under a non-UTF-8 locale such as @C@/@POSIX@.)
readFileUtf8 :: FilePath -> IO Text
readFileUtf8 f = withFile f ReadMode $ \h -> do
  hSetEncoding h utf8
  T.hGetContents h

assertParsesAndRoundTrips :: Text -> Assertion
assertParsesAndRoundTrips src =
  case parseScript "sample" src of
    Left e   -> assertFailure ("parse failed:\n" ++ errorBundlePretty e)
    Right s1 ->
      case parseScript "sample (rerender)" (renderScript s1) of
        Left e   -> assertFailure ("re-parse failed:\n" ++ errorBundlePretty e)
        Right s2 -> map noAnn s1 @?= map noAnn s2
