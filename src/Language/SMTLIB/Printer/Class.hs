{-# LANGUAGE FlexibleInstances #-}

-- | The 'Pretty' class that renders the SMT-LIB AST back to concrete syntax,
-- together with the symbol\/keyword\/string quoting rules.  Annotations are
-- ignored, so @pretty x == pretty (noAnn x)@ for every node.
--
-- Quoting is centralised here ('prettySymbol', 'prettyKeyword',
-- 'prettyStringLit') and always derives the surface form from the /logical/
-- value, which guarantees @parse . render == id@ for well-formed trees.
module Language.SMTLIB.Printer.Class
  ( Pretty(..)
  , prettySymbol
  , prettyKeyword
  , prettyStringLit
  , prettyBool
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Prettyprinter (Doc, (<+>), hsep, parens)
import qualified Prettyprinter as PP

import Language.SMTLIB.Internal.Lexical
  (escapeStringLit, symbolNeedsQuoting)
import Language.SMTLIB.Syntax.Attribute
import Language.SMTLIB.Syntax.Command
import Language.SMTLIB.Syntax.Constant
import Language.SMTLIB.Syntax.Datatype
import Language.SMTLIB.Syntax.Identifier
import Language.SMTLIB.Syntax.Response
import Language.SMTLIB.Syntax.Term

-- | Render an AST node to a 'Doc'.  The renderers in
-- "Language.SMTLIB.Printer" turn the result into 'Text'.
class Pretty a where
  pretty :: a -> Doc ann

text :: Text -> Doc ann
text = PP.pretty

int :: Integer -> Doc ann
int = PP.pretty

-- | Render a symbol, quoting with @|...|@ when it is not a simple symbol.
prettySymbol :: Symbol -> Doc ann
prettySymbol s
  | symbolNeedsQuoting s = text (T.concat ["|", s, "|"])
  | otherwise            = text s

-- | Render a symbol that appears in a @match@ pattern binding position.  The
-- @_@ wildcard (SMT-LIB 2.7) is printed bare; every other symbol follows the
-- usual quoting rules (note @_@ is otherwise a reserved word).
prettyPatternSymbol :: Symbol -> Doc ann
prettyPatternSymbol s
  | s == "_"  = text "_"
  | otherwise = prettySymbol s

-- | Render a keyword (stored without its colon) as @:keyword@.
prettyKeyword :: Keyword -> Doc ann
prettyKeyword k = text (T.cons ':' k)

-- | Render the logical value of a string as a quoted, escaped string literal.
prettyStringLit :: Text -> Doc ann
prettyStringLit s = text (T.concat ["\"", escapeStringLit s, "\""])

-- | Render a boolean as @true@ \/ @false@.
prettyBool :: Bool -> Doc ann
prettyBool True  = text "true"
prettyBool False = text "false"

-- | @(head args...)@, dropping to just @head@ when there are no args.
app :: Doc ann -> [Doc ann] -> Doc ann
app hd [] = hd
app hd xs = parens (hsep (hd : xs))

instance Pretty (SpecConstant a) where
  pretty = \case
    SCNumeral n _     -> int n
    SCDecimal t _     -> text t
    SCHexadecimal t _ -> text (T.append "#x" t)
    SCBinary t _      -> text (T.append "#b" t)
    SCString t _      -> prettyStringLit t

instance Pretty (Index a) where
  pretty = \case
    IxNumeral n _ -> int n
    IxSymbol s _  -> prettySymbol s

instance Pretty (Identifier a) where
  pretty (Identifier s [] _)  = prettySymbol s
  pretty (Identifier s ixs _) =
    parens (hsep (text "_" : prettySymbol s : map pretty ixs))

instance Pretty (Sort a) where
  pretty (Sort i args _) = app (pretty i) (map pretty args)

instance Pretty (QualIdentifier a) where
  pretty = \case
    QIdentifier i _     -> pretty i
    QIdentifierAs i s _ -> parens (text "as" <+> pretty i <+> pretty s)

instance Pretty (SExpr a) where
  pretty = \case
    SEConstant c _ -> pretty c
    SESymbol s _   -> prettySymbol s
    SEKeyword k _  -> prettyKeyword k
    SEReserved s _ -> text s
    SEList xs _    -> parens (hsep (map pretty xs))

instance Pretty (AttributeValue a) where
  pretty = \case
    AVConstant c _ -> pretty c
    AVSymbol s _   -> prettySymbol s
    AVSExpr xs _   -> parens (hsep (map pretty xs))

instance Pretty (Attribute a) where
  pretty = \case
    Attribute k _       -> prettyKeyword k
    AttributeWith k v _ -> prettyKeyword k <+> pretty v

instance Pretty (VarBinding a) where
  pretty (VarBinding s t _) = parens (prettySymbol s <+> pretty t)

instance Pretty (SortedVar a) where
  pretty (SortedVar s srt _) = parens (prettySymbol s <+> pretty srt)

instance Pretty (Pattern a) where
  pretty = \case
    PVar s _     -> prettyPatternSymbol s
    PCtor c xs _ -> parens (hsep (prettySymbol c : map prettyPatternSymbol xs))

instance Pretty (MatchCase a) where
  pretty (MatchCase p t _) = parens (pretty p <+> pretty t)

instance Pretty (Term a) where
  pretty = \case
    TConstant c _  -> pretty c
    TQualIdent q _ -> pretty q
    TApp q args _  -> parens (hsep (pretty q : map pretty args))
    TLet bs t _    ->
      parens (text "let" <+> parens (hsep (map pretty bs)) <+> pretty t)
    TLambda vs t _ ->
      parens (text "lambda" <+> parens (hsep (map pretty vs)) <+> pretty t)
    TForall vs t _ ->
      parens (text "forall" <+> parens (hsep (map pretty vs)) <+> pretty t)
    TExists vs t _ ->
      parens (text "exists" <+> parens (hsep (map pretty vs)) <+> pretty t)
    TMatch t cs _  ->
      parens (text "match" <+> pretty t <+> parens (hsep (map pretty cs)))
    TAnnot t as _  ->
      parens (hsep (text "!" : pretty t : map pretty as))

instance Pretty (SortDec a) where
  pretty (SortDec s n _) = parens (prettySymbol s <+> int n)

instance Pretty (SelectorDec a) where
  pretty (SelectorDec s srt _) = parens (prettySymbol s <+> pretty srt)

instance Pretty (ConstructorDec a) where
  pretty (ConstructorDec s sels _) =
    parens (hsep (prettySymbol s : map pretty sels))

instance Pretty (DatatypeDec a) where
  pretty (DatatypeDec [] ctors _) = parens (hsep (map pretty ctors))
  pretty (DatatypeDec ps ctors _) =
    parens (text "par"
            <+> parens (hsep (map prettySymbol ps))
            <+> parens (hsep (map pretty ctors)))

instance Pretty (FunctionDec a) where
  pretty (FunctionDec s vs srt _) =
    parens (prettySymbol s <+> parens (hsep (map pretty vs)) <+> pretty srt)

-- | A t'FunctionDef' renders /without/ surrounding parens, since the enclosing
-- command supplies them.
instance Pretty (FunctionDef a) where
  pretty (FunctionDef s vs srt t _) =
    prettySymbol s <+> parens (hsep (map pretty vs)) <+> pretty srt <+> pretty t

instance Pretty (PropLiteral a) where
  pretty = \case
    PosLiteral s _ -> prettySymbol s
    NegLiteral s _ -> parens (text "not" <+> prettySymbol s)

instance Pretty (Option a) where
  pretty = \case
    DiagnosticOutputChannel s _   -> text ":diagnostic-output-channel" <+> prettyStringLit s
    GlobalDeclarations b _        -> text ":global-declarations" <+> prettyBool b
    InteractiveMode b _           -> text ":interactive-mode" <+> prettyBool b
    PrintSuccess b _              -> text ":print-success" <+> prettyBool b
    ProduceAssertions b _         -> text ":produce-assertions" <+> prettyBool b
    ProduceAssignments b _        -> text ":produce-assignments" <+> prettyBool b
    ProduceModels b _             -> text ":produce-models" <+> prettyBool b
    ProduceProofs b _             -> text ":produce-proofs" <+> prettyBool b
    ProduceUnsatAssumptions b _   -> text ":produce-unsat-assumptions" <+> prettyBool b
    ProduceUnsatCores b _         -> text ":produce-unsat-cores" <+> prettyBool b
    RandomSeed n _                -> text ":random-seed" <+> int n
    RegularOutputChannel s _      -> text ":regular-output-channel" <+> prettyStringLit s
    ReproducibleResourceLimit n _ -> text ":reproducible-resource-limit" <+> int n
    Verbosity n _                 -> text ":verbosity" <+> int n
    OptionAttribute attr _        -> pretty attr

instance Pretty (InfoFlag a) where
  pretty = \case
    AllStatistics _        -> text ":all-statistics"
    AssertionStackLevels _ -> text ":assertion-stack-levels"
    Authors _              -> text ":authors"
    ErrorBehaviorFlag _    -> text ":error-behavior"
    InfoName _             -> text ":name"
    ReasonUnknownFlag _    -> text ":reason-unknown"
    InfoVersion _          -> text ":version"
    InfoFlagKeyword k _    -> prettyKeyword k

instance Pretty (Command a) where
  pretty = \case
    SetLogic s _            -> parens (text "set-logic" <+> prettySymbol s)
    SetOption o _           -> parens (text "set-option" <+> pretty o)
    SetInfo attr _          -> parens (text "set-info" <+> pretty attr)
    DeclareSort s n _       -> parens (text "declare-sort" <+> prettySymbol s <+> int n)
    DeclareSortParameter s _ -> parens (text "declare-sort-parameter" <+> prettySymbol s)
    DefineSort s args srt _ ->
      parens (text "define-sort" <+> prettySymbol s
              <+> parens (hsep (map prettySymbol args)) <+> pretty srt)
    DeclareConst s srt _    -> parens (text "declare-const" <+> prettySymbol s <+> pretty srt)
    DefineConst s srt t _   ->
      parens (text "define-const" <+> prettySymbol s <+> pretty srt <+> pretty t)
    DeclareFun s args ret _ ->
      parens (text "declare-fun" <+> prettySymbol s
              <+> parens (hsep (map pretty args)) <+> pretty ret)
    DefineFun fd _          -> parens (text "define-fun" <+> pretty fd)
    DefineFunRec fd _       -> parens (text "define-fun-rec" <+> pretty fd)
    DefineFunsRec decs ts _ ->
      parens (text "define-funs-rec"
              <+> parens (hsep (map pretty decs))
              <+> parens (hsep (map pretty ts)))
    DeclareDatatype s dd _  -> parens (text "declare-datatype" <+> prettySymbol s <+> pretty dd)
    DeclareDatatypes sds dds _ ->
      parens (text "declare-datatypes"
              <+> parens (hsep (map pretty sds))
              <+> parens (hsep (map pretty dds)))
    Push n _                -> parens (text "push" <+> int n)
    Pop n _                 -> parens (text "pop" <+> int n)
    Reset _                 -> parens (text "reset")
    ResetAssertions _       -> parens (text "reset-assertions")
    Assert t _              -> parens (text "assert" <+> pretty t)
    CheckSat _              -> parens (text "check-sat")
    CheckSatAssuming ps _   -> parens (text "check-sat-assuming" <+> parens (hsep (map pretty ps)))
    GetAssertions _         -> parens (text "get-assertions")
    GetModel _              -> parens (text "get-model")
    GetProof _              -> parens (text "get-proof")
    GetUnsatCore _          -> parens (text "get-unsat-core")
    GetUnsatAssumptions _   -> parens (text "get-unsat-assumptions")
    GetValue ts _           -> parens (text "get-value" <+> parens (hsep (map pretty ts)))
    GetAssignment _         -> parens (text "get-assignment")
    GetOption k _           -> parens (text "get-option" <+> prettyKeyword k)
    GetInfo flag _          -> parens (text "get-info" <+> pretty flag)
    Echo s _                -> parens (text "echo" <+> prettyStringLit s)
    Exit _                  -> parens (text "exit")

instance Pretty CheckSatResponse where
  pretty Sat     = text "sat"
  pretty Unsat   = text "unsat"
  pretty Unknown = text "unknown"

instance Pretty ErrorBehavior where
  pretty ImmediateExit       = text "immediate-exit"
  pretty ContinuedExecution  = text "continued-execution"

instance Pretty (ReasonUnknown a) where
  pretty = \case
    RUMemout     -> text "memout"
    RUIncomplete -> text "incomplete"
    RUOther e    -> pretty e

instance Pretty (InfoResponse a) where
  pretty = \case
    IRAssertionStackLevels n -> text ":assertion-stack-levels" <+> int n
    IRAuthors s              -> text ":authors" <+> prettyStringLit s
    IRErrorBehavior b        -> text ":error-behavior" <+> pretty b
    IRName s                 -> text ":name" <+> prettyStringLit s
    IRReasonUnknown r        -> text ":reason-unknown" <+> pretty r
    IRVersion s              -> text ":version" <+> prettyStringLit s
    IRAttribute attr         -> pretty attr

instance Pretty (ValuationPair a) where
  pretty (ValuationPair t v) = parens (pretty t <+> pretty v)

instance Pretty (ModelResponse a) where
  pretty = \case
    MRDefineFun fd        -> parens (text "define-fun" <+> pretty fd)
    MRDefineFunRec fd     -> parens (text "define-fun-rec" <+> pretty fd)
    MRDefineFunsRec ds ts ->
      parens (text "define-funs-rec"
              <+> parens (hsep (map pretty ds))
              <+> parens (hsep (map pretty ts)))

instance Pretty (CommandResponse a) where
  pretty = \case
    RSuccess               -> text "success"
    RUnsupported           -> text "unsupported"
    RError s               -> parens (text "error" <+> prettyStringLit s)
    RCheckSat r            -> pretty r
    REcho s                -> prettyStringLit s
    RGetAssertions ts      -> parens (hsep (map pretty ts))
    RGetAssignment ps      -> parens (hsep (map assignPair ps))
    RGetInfo irs           -> parens (hsep (map pretty irs))
    RGetModel ms           -> parens (hsep (map pretty ms))
    RGetOption v           -> pretty v
    RGetProof e            -> pretty e
    RGetUnsatAssumptions ts -> parens (hsep (map pretty ts))
    RGetUnsatCore ss       -> parens (hsep (map prettySymbol ss))
    RGetValue vps          -> parens (hsep (map pretty vps))
    where assignPair (s, b) = parens (prettySymbol s <+> prettyBool b)
