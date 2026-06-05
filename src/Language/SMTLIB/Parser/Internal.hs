-- | The megaparsec lexer and the grammar shared by terms and commands:
-- spec-constants, symbols, keywords, indices, identifiers, sorts, qualified
-- identifiers, s-expressions and attributes.
--
-- Every node parser is wrapped with 'withSpan', so each AST node is annotated
-- with the 'SrcSpan' it was parsed from.  The annotation always occupies the
-- last field of a constructor, which means a fully-applied-but-for-the-span
-- constructor has type @'SrcSpan' -> node 'SrcSpan'@ — exactly what 'withSpan'
-- consumes.
module Language.SMTLIB.Parser.Internal
  ( P
    -- * Lexing
  , sc
  , lexeme
  , withSpan
  , tok
  , openP
  , closeP
  , parens
  , numeral
  , pBool
  , pStringLit
    -- * Lexical tokens
  , pSpecConstant
  , pSymbolRaw
  , pKeyword
    -- * Shared grammar
  , pIndex
  , pIdentifier
  , pSort
  , pQualIdentifier
  , pSExpr
  , pAttribute
  , pAttributeValue
  ) where

import Data.Char (isDigit, isHexDigit)
import Data.Functor (($>))
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.Void (Void)
import Text.Megaparsec
import Text.Megaparsec.Char (char, string)
import qualified Text.Megaparsec.Char.Lexer as L

import Language.SMTLIB.Internal.Lexical
  (isSimpleSymbolChar, isSimpleSymbolStartChar, reservedWords)
import Language.SMTLIB.Syntax.Annotation (SrcSpan(..))
import Language.SMTLIB.Syntax.Attribute
import Language.SMTLIB.Syntax.Constant
import Language.SMTLIB.Syntax.Identifier

-- | The concrete parser monad: megaparsec over strict 'Text' with no custom
-- error component.
type P = Parsec Void Text

-- | The whitespace consumer: spaces and @;@ line comments (SMT-LIB has no block
-- comments).
sc :: P ()
sc = L.space spaceChars (L.skipLineComment ";") empty
  where spaceChars = () <$ takeWhile1P (Just "white space") isWs
        isWs c = c == ' ' || c == '\t' || c == '\n' || c == '\r'

-- | Run a parser then consume trailing whitespace\/comments.
lexeme :: P a -> P a
lexeme = L.lexeme sc

-- | Annotate a node with the source span it covers.  The supplied parser yields
-- a constructor still awaiting its final 'SrcSpan' field.
withSpan :: P (SrcSpan -> a) -> P a
withSpan p = do
  s <- getOffset
  f <- p
  e <- getOffset
  pure (f (SrcSpan s e))

-- | Match a fixed token (keyword or reserved word), ensuring it is not merely a
-- prefix of a longer symbol.
tok :: Text -> P ()
tok w = (lexeme . try) (string w *> notFollowedBy (satisfy isSimpleSymbolChar)) $> ()

openP :: P ()
openP = lexeme (char '(') $> ()

closeP :: P ()
closeP = lexeme (char ')') $> ()

-- | @parens p@ parses @p@ between a balanced pair of parentheses.
parens :: P a -> P a
parens p = openP *> p <* closeP

-- | A numeral (sequence of digits).
numeral :: P Integer
numeral = lexeme (readInteger <$> takeWhile1P (Just "digit") isDigit)

readInteger :: Text -> Integer
readInteger = read . T.unpack

-- | @true@ \/ @false@.
pBool :: P Bool
pBool = (tok "true" $> True) <|> (tok "false" $> False)

isBinDigit :: Char -> Bool
isBinDigit c = c == '0' || c == '1'

-- | A @spec_constant@.  Numeric literals keep their raw lexeme so that printing
-- round-trips exactly.
pSpecConstant :: P (SpecConstant SrcSpan)
pSpecConstant = withSpan (lexeme (pHash <|> pStr <|> pNumDec))
  where
    pHash = char '#' *> (pHex <|> pBin)
    pHex = char 'x' *> (SCHexadecimal <$> takeWhile1P (Just "hex digit") isHexDigit)
    pBin = char 'b' *> (SCBinary <$> takeWhile1P (Just "binary digit") isBinDigit)
    pStr = SCString <$> pStringBody
    pNumDec = do
      intp <- takeWhile1P (Just "digit") isDigit
      mfrac <- optional (char '.' *> takeWhileP (Just "digit") isDigit)
      pure $ case mfrac of
        Nothing -> SCNumeral (readInteger intp)
        Just fr -> SCDecimal (T.concat [intp, ".", fr])

-- | The body of a string literal (no trailing whitespace), decoding @""@ into a
-- single quote.
pStringBody :: P Text
pStringBody = char '"' *> go
  where
    go = do
      seg <- takeWhileP (Just "string char") (/= '"')
      _ <- char '"'
      mq <- optional (char '"')
      case mq of
        Just _  -> (\rest -> T.concat [seg, "\"", rest]) <$> go
        Nothing -> pure seg

-- | A string literal as a lexeme.
pStringLit :: P Text
pStringLit = lexeme pStringBody

-- | A symbol (simple or @|...|@ quoted), returning its logical value.  Simple
-- symbols that are reserved words are rejected so the grammar's keywords are
-- not swallowed.
pSymbolRaw :: P Symbol
pSymbolRaw = lexeme (pSimple <|> pQuoted)
  where
    pSimple = try $ do
      h <- satisfy isSimpleSymbolStartChar
      t <- takeWhileP (Just "symbol char") isSimpleSymbolChar
      let s = T.cons h t
      if s `Set.member` reservedWords
        then fail ("reserved word " ++ T.unpack s)
        else pure s
    pQuoted = quotedBody

-- | A @|...|@ quoted symbol body, returning its logical value.
quotedBody :: P Text
quotedBody = char '|' *> takeWhileP (Just "quoted-symbol char") (\c -> c /= '|' && c /= '\\') <* char '|'

-- | A simple word /including/ reserved words (used inside s-expressions).
pAnyWord :: P Text
pAnyWord = lexeme $ do
  h <- satisfy isSimpleSymbolStartChar
  t <- takeWhileP (Just "symbol char") isSimpleSymbolChar
  pure (T.cons h t)

-- | A keyword, returned without its leading colon.
pKeyword :: P Keyword
pKeyword = lexeme (char ':' *> takeWhile1P (Just "keyword char") isSimpleSymbolChar)

-- | An @index@: a numeral or a symbol.
pIndex :: P (Index SrcSpan)
pIndex = withSpan ((IxNumeral <$> numeral) <|> (IxSymbol <$> pSymbolRaw))

-- | An @identifier@: a symbol, or @(_ symbol index+)@.
pIdentifier :: P (Identifier SrcSpan)
pIdentifier = withSpan (plain <|> indexed)
  where
    plain   = (\s -> Identifier s []) <$> pSymbolRaw
    indexed = do
      _ <- openP
      _ <- tok "_"
      s <- pSymbolRaw
      ixs <- some pIndex
      _ <- closeP
      pure (Identifier s ixs)

-- | A @sort@: an identifier, or @(identifier sort+)@.
pSort :: P (Sort SrcSpan)
pSort = withSpan (try simple <|> param)
  where
    simple = (\i -> Sort i []) <$> pIdentifier
    param  = parens (Sort <$> pIdentifier <*> some pSort)

-- | A @qual_identifier@: an identifier or @(as identifier sort)@.
pQualIdentifier :: P (QualIdentifier SrcSpan)
pQualIdentifier = withSpan (try asForm <|> plain)
  where
    asForm = parens (tok "as" *> (QIdentifierAs <$> pIdentifier <*> pSort))
    plain  = QIdentifier <$> pIdentifier

-- | An @s_expr@.
pSExpr :: P (SExpr SrcSpan)
pSExpr = withSpan $ choice
  [ SEConstant <$> pSpecConstant
  , SEKeyword  <$> pKeyword
  , SEList     <$> parens (many pSExpr)
  , wordOrReserved
  , SESymbol   <$> lexeme quotedBody
  ]
  where
    wordOrReserved = do
      w <- pAnyWord
      pure (if w `Set.member` reservedWords then SEReserved w else SESymbol w)

-- | An @attribute_value@.
pAttributeValue :: P (AttributeValue SrcSpan)
pAttributeValue = withSpan $ choice
  [ AVConstant <$> pSpecConstant
  , AVSExpr    <$> parens (many pSExpr)
  , AVSymbol   <$> pSymbolRaw
  ]

-- | An @attribute@: a keyword, optionally followed by a value.
pAttribute :: P (Attribute SrcSpan)
pAttribute = withSpan $ do
  k  <- pKeyword
  mv <- optional pAttributeValue
  pure (maybe (Attribute k) (AttributeWith k) mv)
