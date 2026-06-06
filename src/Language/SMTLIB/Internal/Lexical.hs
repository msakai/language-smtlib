-- | Lexical conventions shared by the parser and the printer: the reserved-word
-- set, the simple-symbol character classes, and string-literal escaping.  This
-- is the single source of truth so the two sides cannot drift apart.
module Language.SMTLIB.Internal.Lexical
  ( reservedWords
  , isSimpleSymbolChar
  , isSimpleSymbolStartChar
  , isSimpleSymbol
  , symbolNeedsQuoting
  , escapeStringLit
  , unescapeStringLit
  ) where

import Data.Char (isAlpha, isDigit)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

-- | The SMT-LIB 2.7 reserved words: the auxiliary tokens plus every command
-- name.  A simple symbol may not coincide with one of these, so a @Symbol@
-- whose value is a reserved word must be printed quoted.
--
-- Note: @lambda@ is treated as a reserved word here, consistently with the
-- other binders (@forall@\/@exists@\/@let@\/@match@), so that a @(lambda ...)@
-- term round-trips unambiguously.  The Version 2.7 concrete-syntax appendix
-- omits @lambda@ from its reserved-word list, but the term grammar gives it a
-- dedicated binder production, so we follow the grammar.
reservedWords :: Set Text
reservedWords = Set.fromList $
  -- auxiliary / general reserved words
  [ "!", "_", "as", "BINARY", "DECIMAL", "exists", "forall"
  , "HEXADECIMAL", "lambda", "let", "match", "NUMERAL", "par", "STRING"
  ] ++
  -- command names
  [ "assert", "check-sat", "check-sat-assuming"
  , "declare-const", "declare-datatype", "declare-datatypes"
  , "declare-fun", "declare-sort", "declare-sort-parameter"
  , "define-const", "define-fun", "define-fun-rec", "define-funs-rec"
  , "define-sort"
  , "echo", "exit"
  , "get-assertions", "get-assignment", "get-info", "get-model"
  , "get-option", "get-proof", "get-unsat-assumptions", "get-unsat-core"
  , "get-value", "pop", "push", "reset", "reset-assertions"
  , "set-info", "set-logic", "set-option"
  ]

-- | The non-alphanumeric characters permitted in a simple symbol.
specialChars :: String
specialChars = "~!@$%^&*_-+=<>.?/"

-- | Whether @c@ may appear anywhere in a simple symbol.
--
-- The SMT-LIB 2 standard restricts simple-symbol letters to ASCII; as a
-- documented, benign superset (matching what solvers such as z3 accept) we also
-- admit any Unicode letter, so identifiers like @あいうえお@ need no quoting.
isSimpleSymbolChar :: Char -> Bool
isSimpleSymbolChar c =
  isAlpha c || isDigit c || c `elem` specialChars

-- | Whether @c@ may appear as the /first/ character of a simple symbol (i.e. a
-- simple-symbol character that is not a digit).
isSimpleSymbolStartChar :: Char -> Bool
isSimpleSymbolStartChar c = isSimpleSymbolChar c && not (isDigit c)

-- | Whether a symbol can be rendered without @|...|@ quoting: non-empty, made
-- only of simple-symbol characters, not starting with a digit, and not a
-- reserved word.
isSimpleSymbol :: Text -> Bool
isSimpleSymbol t = case T.uncons t of
  Nothing      -> False
  Just (c, cs) ->
    isSimpleSymbolStartChar c
      && T.all isSimpleSymbolChar cs
      && t `Set.notMember` reservedWords

-- | Whether a symbol must be quoted on output (the negation of 'isSimpleSymbol').
symbolNeedsQuoting :: Text -> Bool
symbolNeedsQuoting = not . isSimpleSymbol

-- | Encode the logical value of a string literal into its quoted body by
-- doubling every double-quote.  (Does not add the surrounding quotes.)
escapeStringLit :: Text -> Text
escapeStringLit = T.replace "\"" "\"\""

-- | Decode the body of a string literal (the text between the surrounding
-- quotes) by collapsing every doubled double-quote back into one.
unescapeStringLit :: Text -> Text
unescapeStringLit = T.replace "\"\"" "\""
