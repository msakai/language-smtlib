-- | Lexical constants of the SMT-LIB 2 language: symbols, keywords, indices and
-- spec-constants, plus helpers to interpret the numeric literals.
--
-- 'Symbol', 'Keyword' and the string payload of 'SCString' always hold the
-- /logical/ value (unquoted, unescaped).  Quoting and escaping is entirely the
-- printer's responsibility.  The numeric literals 'SCDecimal', 'SCHexadecimal'
-- and 'SCBinary' keep the raw lexeme 'Text' so that printing round-trips
-- byte-for-byte (leading zeros, letter case); use the interpreters below to
-- recover their values.
module Language.SMTLIB.Syntax.Constant
  ( Symbol
  , Keyword
  , SpecConstant(..)
  , Index(..)
    -- * Numeric interpreters
  , hexToInteger
  , binToInteger
  , decimalToScientific
  ) where

import Data.Char (digitToInt)
import Data.Hashable (Hashable)
import Data.Scientific (Scientific)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import Language.SMTLIB.Syntax.Annotation (Annotated(..))

-- | An SMT-LIB symbol, stored as its logical (unquoted) value.
type Symbol = Text

-- | An SMT-LIB keyword, stored /without/ its leading colon.
type Keyword = Text

-- | A @spec_constant@.
data SpecConstant a
  = SCNumeral     !Integer a  -- ^ @42@
  | SCDecimal     !Text    a  -- ^ raw lexeme, e.g. @"1.500"@
  | SCHexadecimal !Text    a  -- ^ digits only (no @#x@), e.g. @"00aF"@
  | SCBinary      !Text    a  -- ^ digits only (no @#b@), e.g. @"0110"@
  | SCString      !Text    a  -- ^ decoded string value (no quotes, @""@ unescaped)
  deriving (Show, Eq, Ord, Functor, Foldable, Traversable, Generic)

-- | An @index@ of an indexed identifier @(_ sym i ...)@.
data Index a
  = IxNumeral !Integer a
  | IxSymbol  !Symbol  a
  deriving (Show, Eq, Ord, Functor, Foldable, Traversable, Generic)

instance Hashable a => Hashable (SpecConstant a)
instance Hashable a => Hashable (Index a)

instance Annotated SpecConstant where
  ann = \case
    SCNumeral _ a     -> a
    SCDecimal _ a     -> a
    SCHexadecimal _ a -> a
    SCBinary _ a      -> a
    SCString _ a      -> a
  setAnn a = \case
    SCNumeral x _     -> SCNumeral x a
    SCDecimal x _     -> SCDecimal x a
    SCHexadecimal x _ -> SCHexadecimal x a
    SCBinary x _      -> SCBinary x a
    SCString x _      -> SCString x a

instance Annotated Index where
  ann = \case
    IxNumeral _ a -> a
    IxSymbol _ a  -> a
  setAnn a = \case
    IxNumeral x _ -> IxNumeral x a
    IxSymbol x _  -> IxSymbol x a

-- | Interpret the digits of an 'SCHexadecimal' lexeme as an 'Integer'.
hexToInteger :: Text -> Integer
hexToInteger = T.foldl' (\acc c -> acc * 16 + toInteger (digitToInt c)) 0

-- | Interpret the digits of an 'SCBinary' lexeme as an 'Integer'.
binToInteger :: Text -> Integer
binToInteger = T.foldl' (\acc c -> acc * 2 + toInteger (digitToInt c)) 0

-- | Interpret an 'SCDecimal' lexeme as a 'Scientific' value.
decimalToScientific :: Text -> Scientific
decimalToScientific = read . T.unpack
