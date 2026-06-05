-- | Rendering the SMT-LIB AST to 'Text'.
--
-- The default layout puts each top-level form on a single line (no automatic
-- line breaks), which keeps the output deterministic and trivially
-- round-trippable.  'RenderOptions' lets callers opt into a wrapped layout.
module Language.SMTLIB.Printer
  ( Pretty(..)
  , RenderOptions(..)
  , defaultRenderOptions
  , render
  , renderText
  , renderTextWith
  , renderScript
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Prettyprinter (Doc, LayoutOptions(..), PageWidth(..), layoutPretty)
import Prettyprinter.Render.Text (renderStrict)

import Language.SMTLIB.Printer.Class (Pretty(..))
import Language.SMTLIB.Syntax.Command (Script)

-- | Layout configuration.
newtype RenderOptions = RenderOptions
  { roPageWidth :: PageWidth
    -- ^ 'Unbounded' (the default) keeps every form on one line.
  }

-- | Single-line layout: each form rendered without automatic wrapping.
defaultRenderOptions :: RenderOptions
defaultRenderOptions = RenderOptions { roPageWidth = Unbounded }

-- | Render any 'Doc' to 'Text' with the given options.
render :: RenderOptions -> Doc ann -> Text
render opts = renderStrict . layoutPretty layoutOpts
  where layoutOpts = LayoutOptions { layoutPageWidth = roPageWidth opts }

-- | Render a single AST node to 'Text' using 'defaultRenderOptions'.
renderText :: Pretty a => a -> Text
renderText = renderTextWith defaultRenderOptions

-- | Render a single AST node to 'Text' with explicit options.
renderTextWith :: Pretty a => RenderOptions -> a -> Text
renderTextWith opts = render opts . pretty

-- | Render a whole script, one command per line, terminated by a newline.
renderScript :: Script a -> Text
renderScript [] = T.empty
renderScript cmds = T.unlines (map renderText cmds)
