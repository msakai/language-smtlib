{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Size-bounded 'Arbitrary' generators for the @()@-annotated AST, used by the
-- round-trip property tests.  Symbols and string values are generated as their
-- /logical/ values (including ones that force the printer to quote\/escape), so
-- the round-trip property exercises the quoting rules.
module Arbitrary () where

import qualified Data.Text as T
import Test.QuickCheck

import Language.SMTLIB.Syntax

-- Characters -----------------------------------------------------------------

startChars :: [Char]
startChars = ['a'..'z'] ++ ['A'..'Z'] ++ "~!@$%^&*_-+=<>.?/"

contChars :: [Char]
contChars = startChars ++ ['0'..'9']

-- Includes characters that force |...| quoting (space, ':', '#', '"', digit
-- leads) but never '|' or '\\', which are not representable inside a quoted
-- symbol.
weirdChars :: [Char]
weirdChars = contChars ++ " :#\"0123456789"

genSymbol :: Gen Symbol
genSymbol = oneof [simple, weird]
  where
    simple = do
      h <- elements startChars
      t <- resize 3 (listOf (elements contChars))
      pure (T.pack (h : t))
    weird = T.pack <$> resize 4 (listOf1 (elements weirdChars))

-- | A symbol usable in a @match@ pattern binding position: an ordinary symbol
-- or the @_@ wildcard (SMT-LIB 2.7).
genPatternSymbol :: Gen Symbol
genPatternSymbol = frequency [(1, pure "_"), (4, genSymbol)]

genKeyword :: Gen Keyword
genKeyword = T.pack <$> resize 4 (listOf1 (elements contChars))

genStringValue :: Gen T.Text
genStringValue = T.pack <$> resize 6 (listOf (elements stringChars))
  where stringChars = ['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ " \t\"()|;"

genDigits :: Gen T.Text
genDigits = T.pack <$> resize 4 (listOf1 (elements ['0'..'9']))

-- Bounded list helpers -------------------------------------------------------

listOf1' :: Int -> Gen a -> Gen [a]
listOf1' n g = choose (1, max 1 n) >>= \k -> vectorOf k g

listOf' :: Int -> Gen a -> Gen [a]
listOf' n g = choose (0, n) >>= \k -> vectorOf k g

-- Constants ------------------------------------------------------------------

instance Arbitrary (SpecConstant ()) where
  arbitrary = oneof
    [ (\n -> SCNumeral n ()) . getNonNegative <$> arbitrary
    , (\i f -> SCDecimal (T.concat [i, ".", f]) ()) <$> genDigits <*> genDigits
    , (\t -> SCHexadecimal t ()) . T.pack <$> resize 4 (listOf1 (elements "0123456789abcdefABCDEF"))
    , (\t -> SCBinary t ()) . T.pack <$> resize 4 (listOf1 (elements "01"))
    , (\s -> SCString s ()) <$> genStringValue
    ]

instance Arbitrary (Index ()) where
  arbitrary = oneof
    [ (\n -> IxNumeral n ()) . getNonNegative <$> arbitrary
    , (\s -> IxSymbol s ()) <$> genSymbol
    ]

-- Identifiers and sorts ------------------------------------------------------

instance Arbitrary (Identifier ()) where
  arbitrary = Identifier <$> genSymbol <*> listOf' 2 arbitrary <*> pure ()

instance Arbitrary (Sort ()) where
  arbitrary = sized go
    where
      go n
        | n <= 0    = (\i -> Sort i [] ()) <$> arbitrary
        | otherwise = do
            i <- arbitrary
            args <- listOf' 2 (resize (n `div` 2) (sized go))
            pure (Sort i args ())

instance Arbitrary (QualIdentifier ()) where
  arbitrary = oneof
    [ (\i -> QIdentifier i ()) <$> arbitrary
    , (\i s -> QIdentifierAs i s ()) <$> arbitrary <*> arbitrary
    ]

-- S-expressions and attributes -----------------------------------------------

instance Arbitrary (SExpr ()) where
  arbitrary = sized go
    where
      go n
        | n <= 0 = oneof
            [ (\c -> SEConstant c ()) <$> arbitrary
            , (\k -> SEKeyword k ()) <$> genKeyword
            , (\s -> SESymbol s ()) <$> genSymbol
            , (\w -> SEReserved w ()) <$> elements reservedList
            ]
        | otherwise = oneof
            [ (\c -> SEConstant c ()) <$> arbitrary
            , (\k -> SEKeyword k ()) <$> genKeyword
            , (\s -> SESymbol s ()) <$> genSymbol
            , (\w -> SEReserved w ()) <$> elements reservedList
            , (\xs -> SEList xs ()) <$> listOf' 3 (resize (n `div` 2) (sized go))
            ]
      reservedList = ["_", "as", "let", "lambda", "forall", "exists", "match", "par", "!"]

instance Arbitrary (AttributeValue ()) where
  arbitrary = oneof
    [ (\c -> AVConstant c ()) <$> arbitrary
    , (\s -> AVSymbol s ()) <$> genSymbol
    , (\xs -> AVSExpr xs ()) <$> resize 3 (listOf' 3 arbitrary)
    ]

instance Arbitrary (Attribute ()) where
  arbitrary = oneof
    [ (\k -> Attribute k ()) <$> genKeyword
    , (\k v -> AttributeWith k v ()) <$> genKeyword <*> arbitrary
    ]

-- Terms ----------------------------------------------------------------------

instance Arbitrary (VarBinding ()) where
  arbitrary = VarBinding <$> genSymbol <*> resize 2 arbitrary <*> pure ()

instance Arbitrary (SortedVar ()) where
  arbitrary = SortedVar <$> genSymbol <*> resize 2 arbitrary <*> pure ()

instance Arbitrary (Pattern ()) where
  arbitrary = oneof
    [ (\s -> PVar s ()) <$> genPatternSymbol
    , (\c xs -> PCtor c xs ()) <$> genSymbol <*> listOf1' 2 genPatternSymbol
    ]

instance Arbitrary (MatchCase ()) where
  arbitrary = MatchCase <$> arbitrary <*> resize 2 arbitrary <*> pure ()

instance Arbitrary (Term ()) where
  arbitrary = sized go
    where
      leaf = oneof
        [ (\c -> TConstant c ()) <$> arbitrary
        , (\q -> TQualIdent q ()) <$> arbitrary
        ]
      go n
        | n <= 0    = leaf
        | otherwise = oneof
            [ leaf
            , (\q ts -> TApp q ts ()) <$> arbitrary <*> listOf1' 3 (sub n)
            , (\bs t -> TLet bs t ()) <$> listOf1' 2 (resize (n `div` 2) arbitrary) <*> sub n
            , (\vs t -> TLambda vs t ()) <$> listOf1' 2 (resize (n `div` 2) arbitrary) <*> sub n
            , (\vs t -> TForall vs t ()) <$> listOf1' 2 (resize (n `div` 2) arbitrary) <*> sub n
            , (\vs t -> TExists vs t ()) <$> listOf1' 2 (resize (n `div` 2) arbitrary) <*> sub n
            , (\t cs -> TMatch t cs ()) <$> sub n <*> listOf1' 2 (resize (n `div` 2) arbitrary)
            , (\t as -> TAnnot t as ()) <$> sub n <*> listOf1' 2 (resize (n `div` 2) arbitrary)
            ]
      sub n = resize (n `div` 2) (sized go)

-- Datatype / function declarations -------------------------------------------

instance Arbitrary (SortDec ()) where
  arbitrary = SortDec <$> genSymbol <*> (getNonNegative <$> arbitrary) <*> pure ()

instance Arbitrary (SelectorDec ()) where
  arbitrary = SelectorDec <$> genSymbol <*> resize 2 arbitrary <*> pure ()

instance Arbitrary (ConstructorDec ()) where
  arbitrary = ConstructorDec <$> genSymbol <*> listOf' 2 arbitrary <*> pure ()

instance Arbitrary (DatatypeDec ()) where
  arbitrary = oneof
    [ (\cs -> DatatypeDec [] cs ()) <$> listOf1' 2 arbitrary
    , (\ps cs -> DatatypeDec ps cs ()) <$> listOf1' 2 genSymbol <*> listOf1' 2 arbitrary
    ]

instance Arbitrary (FunctionDec ()) where
  arbitrary = FunctionDec <$> genSymbol <*> listOf' 2 arbitrary <*> resize 2 arbitrary <*> pure ()

instance Arbitrary (FunctionDef ()) where
  arbitrary = FunctionDef <$> genSymbol <*> listOf' 2 arbitrary
                          <*> resize 2 arbitrary <*> resize 2 arbitrary <*> pure ()

-- Commands -------------------------------------------------------------------

instance Arbitrary (PropLiteral ()) where
  arbitrary = oneof
    [ (\s -> PosLiteral s ()) <$> genSymbol
    , (\s -> NegLiteral s ()) <$> genSymbol
    ]

instance Arbitrary (Option ()) where
  arbitrary = oneof
    [ b PrintSuccess, b GlobalDeclarations, b InteractiveMode
    , b ProduceAssertions, b ProduceAssignments, b ProduceModels, b ProduceProofs
    , b ProduceUnsatAssumptions, b ProduceUnsatCores
    , (\s -> DiagnosticOutputChannel s ()) <$> genStringValue
    , (\s -> RegularOutputChannel s ()) <$> genStringValue
    , n RandomSeed, n Verbosity, n ReproducibleResourceLimit
    , (\a -> OptionAttribute a ()) <$> arbitrary
    ]
    where
      b con = (\x -> con x ()) <$> arbitrary
      n con = (\x -> con x ()) . getNonNegative <$> arbitrary

instance Arbitrary (InfoFlag ()) where
  arbitrary = oneof
    [ pure (AllStatistics ()), pure (AssertionStackLevels ()), pure (Authors ())
    , pure (ErrorBehaviorFlag ()), pure (InfoName ()), pure (ReasonUnknownFlag ())
    , pure (InfoVersion ()), (\k -> InfoFlagKeyword k ()) <$> genKeyword
    ]

instance Arbitrary (Command ()) where
  arbitrary = oneof
    [ (\s -> SetLogic s ()) <$> genSymbol
    , (\o -> SetOption o ()) <$> arbitrary
    , (\a -> SetInfo a ()) <$> arbitrary
    , (\s k -> DeclareSort s k ()) <$> genSymbol <*> (getNonNegative <$> arbitrary)
    , (\s -> DeclareSortParameter s ()) <$> genSymbol
    , (\s ps r -> DefineSort s ps r ()) <$> genSymbol <*> listOf' 2 genSymbol <*> arbitrary
    , (\s r -> DeclareConst s r ()) <$> genSymbol <*> arbitrary
    , (\s r t -> DefineConst s r t ()) <$> genSymbol <*> arbitrary <*> resize 2 arbitrary
    , (\s as r -> DeclareFun s as r ()) <$> genSymbol <*> listOf' 2 arbitrary <*> arbitrary
    , (\d -> DefineFun d ()) <$> arbitrary
    , (\d -> DefineFunRec d ()) <$> arbitrary
    , funsRec
    , (\s d -> DeclareDatatype s d ()) <$> genSymbol <*> arbitrary
    , datatypes
    , (\k -> Push k ()) . getNonNegative <$> arbitrary
    , (\k -> Pop k ()) . getNonNegative <$> arbitrary
    , pure (Reset ()), pure (ResetAssertions ())
    , (\t -> Assert t ()) <$> arbitrary
    , pure (CheckSat ())
    , (\ps -> CheckSatAssuming ps ()) <$> listOf' 3 arbitrary
    , pure (GetAssertions ()), pure (GetModel ()), pure (GetProof ())
    , pure (GetUnsatCore ()), pure (GetUnsatAssumptions ())
    , (\ts -> GetValue ts ()) <$> listOf1' 3 arbitrary
    , pure (GetAssignment ())
    , (\k -> GetOption k ()) <$> genKeyword
    , (\f -> GetInfo f ()) <$> arbitrary
    , (\s -> Echo s ()) <$> genStringValue
    , pure (Exit ())
    ]
    where
      funsRec = do
        k <- choose (1, 2)
        DefineFunsRec <$> vectorOf k arbitrary <*> vectorOf k arbitrary <*> pure ()
      datatypes = do
        k <- choose (1, 2)
        DeclareDatatypes <$> vectorOf k arbitrary <*> vectorOf k arbitrary <*> pure ()
