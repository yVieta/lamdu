{-# LANGUAGE TypeApplications, FlexibleInstances, MultiParamTypeClasses, DefaultSignatures, ScopedTypeVariables, UndecidableInstances #-}

module Lamdu.Sugar.OrderTags
    ( orderDef, orderType, orderNode
    ) where

import qualified Control.Lens as Lens
import           Control.Monad ((>=>))
import           Control.Monad.Transaction (MonadTransaction(..))
import           Data.Property (mkProperty, pVal, pSet)
import           Data.List (sortOn)
import           Hyper
import qualified Lamdu.Calc.Type as T
import qualified Lamdu.Data.Anchors as Anchors
import qualified Lamdu.Data.Ops as DataOps
import           Lamdu.Data.Tag (tagOrder)
import qualified Lamdu.Expr.IRef as ExprIRef
import qualified Lamdu.Sugar.Lens as SugarLens
import qualified Lamdu.Sugar.Types as Sugar

import           Lamdu.Prelude

type OrderT m x = x -> m x

class Order i t where
    order :: OrderT i (t # Annotated a)

    default order ::
        ( MonadTransaction m i, HTraversable t
        , HNodesConstraint t (Order i)
        ) =>
        OrderT i (t # Annotated a)
    order = htraverse (Proxy @(Order i) #> orderNode)

orderByTag :: MonadTransaction m i => (a -> Sugar.Tag name) -> (a -> i b) -> [a] -> i [b]
orderByTag toTag ord =
    fmap (map fst . sortOn snd) . traverse f
    where
        f x =
            (,)
            <$> ord x
            <*> (toTag x ^. Sugar.tagVal & ExprIRef.readTagData & transaction)

orderComposite ::
    MonadTransaction m i =>
    OrderT i (Sugar.CompositeFields name (Ann a # Sugar.Type name o))
orderComposite = Sugar.compositeFields (orderByTag fst (_2 orderType))

orderTBody ::
    MonadTransaction m i =>
    OrderT i (Sugar.Type name o # Ann a)
orderTBody t =
    t
    & Sugar._TRecord %%~ orderComposite
    >>= Sugar._TVariant %%~ orderComposite
    >>= htraverse1 orderType

orderType :: MonadTransaction m i => OrderT i (Ann a # Sugar.Type name o)
orderType = hVal orderTBody

orderTaggedList ::
    (MonadTransaction m f, Applicative o) =>
    (a -> f a) -> Sugar.TaggedList name i o a -> f (Sugar.TaggedList name i o a)
orderTaggedList orderItem (Sugar.TaggedList addFirst items) =
    Sugar.TaggedList addFirst <$> Lens._Just (orderTaggedListBody orderItem) items

orderTaggedListBody ::
    (MonadTransaction m f, Applicative o) =>
    (a -> f a) -> Sugar.TaggedListBody name i o a -> f (Sugar.TaggedListBody name i o a)
orderTaggedListBody orderItem tlb =
    orderByTag (^. Sugar.tiTag . Sugar.tagRefTag) (Sugar.tiValue orderItem) (tlb ^.. SugarLens.taggedListBodyItems) <&>
    \(newHd : newTl) ->
    newTl <&> (`Sugar.TaggedSwappableItem` pure ())
    & Sugar.TaggedListBody newHd

instance (MonadTransaction m o, MonadTransaction m i) => Order i (Sugar.Composite v name i o) where
    order (Sugar.Composite items punned tail_) =
        Sugar.Composite
        <$> orderTaggedList orderNode items
        <*> pure punned
        <*> Sugar._OpenComposite orderNode tail_

instance (MonadTransaction m o, MonadTransaction m i) => Order i (Sugar.LabeledApply v name i o) where
    order (Sugar.LabeledApply func specialArgs annotated punned) =
        Sugar.LabeledApply func
        <$> (Lens._Just . htraverse1) orderNode specialArgs
        <*> orderByTag (^. Sugar.aaTag) (Sugar.aaExpr orderNode) annotated
        ?? punned

instance MonadTransaction m i => Order i (Const a)
instance (MonadTransaction m o, MonadTransaction m i) => Order i (Sugar.Else v name i o)
instance (MonadTransaction m o, MonadTransaction m i) => Order i (Sugar.IfElse v name i o)
instance (MonadTransaction m o, MonadTransaction m i) => Order i (Sugar.Let v name i o)
instance (MonadTransaction m o, MonadTransaction m i) => Order i (Sugar.PostfixApply v name i o)

instance (MonadTransaction m o, MonadTransaction m i) => Order i (Sugar.Lambda v name i o) where
    order = Sugar.lamFunc order

instance (MonadTransaction m o, MonadTransaction m i) => Order i (Sugar.Function v name i o) where
    order x =
        (Sugar.fParams . Sugar._RecordParams) (orderByTag (^. _2 . Sugar.piTag . Sugar.tagRefTag) pure) x
        >>= Sugar.fBody orderNode
        <&> Sugar.fParams . Sugar._RecordParams %~ addReorders

tagChoiceOptions ::
    Lens.Setter
    (Sugar.TagChoice n0 o) (Sugar.TagChoice n1 o)
    (Sugar.TagOption n0 o) (Sugar.TagOption n1 o)
tagChoiceOptions =
    Lens.setting (\f (Sugar.TagChoice o n) -> Sugar.TagChoice (o <&> f) (f n))

tagChoicePick :: Lens.IndexedSetter' T.Tag (Sugar.TagChoice n o) (o ())
tagChoicePick = tagChoiceOptions . Lens.filteredBy (Sugar.toInfo . Sugar.tagVal) <. Sugar.toPick

addReorders ::
    (MonadTransaction m o, Functor i) =>
    [(a, Sugar.RecordParamInfo n i o)] -> [(a, Sugar.RecordParamInfo n i o)]
addReorders params =
    params & Lens.itraversed <. _2 %@~ addParamActions
    where
        tags = params ^.. traverse . _2 . Sugar.piTag . Sugar.tagRefTag . Sugar.tagVal
        addParamActions ::
            (MonadTransaction m o, Functor i) =>
            Int -> Sugar.RecordParamInfo n i o -> Sugar.RecordParamInfo n i o
        addParamActions i a =
            a
            & Sugar.piTag . Sugar.tagRefReplace . Lens.mapped . tagChoicePick %@~
                (\t ->
                    (transaction (
                        ExprIRef.readTagData (a ^. Sugar.piTag . Sugar.tagRefTag . Sugar.tagVal)
                        <&> (^. tagOrder) >>= DataOps.setTagOrder t) >>))
            & Sugar.piAddNext . Lens.mapped . tagChoicePick %@~
                (\t -> (transaction (Lens.itraverse_ (flip DataOps.setTagOrder) (before <> [t] <> after)) >>))
            & Sugar.piMOrderBefore .~
                (setOrder ([0..i-1] <> [i, i-1] <> [i+1..length tags-1]) <$ guard (i > 0))
            & Sugar.piMOrderAfter .~
                (setOrder ([0..i] <> [i+1, i] <> [i+2..length tags-1]) <$ guard (i + 1 < length tags))
            where
                (before, after) = splitAt (i+1) tags
        setOrder :: MonadTransaction m o => [Int] -> o ()
        setOrder o =
            Lens.itraverse_ (flip DataOps.setTagOrder) (o <&> \i -> tags ^?! Lens.ix i)
            & transaction

instance (MonadTransaction m o, MonadTransaction m i) => Order i (Sugar.PostfixFunc v name i o) where
    order (Sugar.PfCase x) = order x <&> Sugar.PfCase
    order x@Sugar.PfFromNom{} = pure x
    order x@Sugar.PfGetField{} = pure x

-- Special case assignment and binder to invoke the special cases in expr

instance (MonadTransaction m o, MonadTransaction m i) => Order i (Sugar.Assignment v name i o) where
    order (Sugar.BodyPlain x) = Sugar.apBody order x <&> Sugar.BodyPlain
    order (Sugar.BodyFunction x) = order x <&> Sugar.BodyFunction

instance (MonadTransaction m o, MonadTransaction m i) => Order i (Sugar.Binder v name i o) where
    order (Sugar.BinderTerm x) = order x <&> Sugar.BinderTerm
    order (Sugar.BinderLet x) = order x <&> Sugar.BinderLet

instance (MonadTransaction m o, MonadTransaction m i) => Order i (Sugar.Term v name i o) where
    order (Sugar.BodyLam l) = order l <&> Sugar.BodyLam
    order (Sugar.BodyRecord r) = order r <&> Sugar.BodyRecord
    order (Sugar.BodyLabeledApply a) = order a <&> Sugar.BodyLabeledApply
    order (Sugar.BodyPostfixFunc f) = order f <&> Sugar.BodyPostfixFunc
    order (Sugar.BodyFragment a) =
        a
        & Sugar.fOptions . Lens.mapped . Lens.mapped
            %~ (>>= (traverse . Sugar.optionExpr) orderNode)
        & Sugar.fExpr orderNode
        <&> Sugar.BodyFragment
    order (Sugar.BodyIfElse x) = order x <&> Sugar.BodyIfElse
    order (Sugar.BodyToNom x) = Sugar.nVal orderNode x <&> Sugar.BodyToNom
    order (Sugar.BodySimpleApply x) = htraverse1 orderNode x <&> Sugar.BodySimpleApply
    order (Sugar.BodyPostfixApply x) = order x <&> Sugar.BodyPostfixApply
    order (Sugar.BodyNullaryInject x) = Sugar.BodyNullaryInject x & pure
    order (Sugar.BodyLeaf x) =
        x
        & Sugar._LeafHole . Sugar.holeOptions . Lens.mapped . Lens.mapped
            %~ (>>= (traverse . Sugar.optionExpr) orderNode)
        & Sugar.BodyLeaf
        & pure

instance (MonadTransaction m o, MonadTransaction m i) => Order i (Sugar.FragOpt v name i o)

orderNode ::
    (MonadTransaction m i, Order i f) =>
    OrderT i (Annotated a # f)
orderNode = hVal order

orderDef ::
    (MonadTransaction m o, MonadTransaction m i) =>
    OrderT i (Sugar.Definition v name i o a)
orderDef def =
    def
    & (SugarLens.defSchemes . Sugar.schemeType) orderType
    >>= (Sugar.drBody . Sugar._DefinitionBodyExpression . Sugar.deContent)
        (orderNode >=> (hVal . Sugar._BodyFunction . Sugar.fParams . Sugar._RecordParams) processPresentationMode)
    where
        processPresentationMode orig =
            Anchors.assocPresentationMode (def ^. Sugar.drDefI) ^. mkProperty & transaction <&>
            \presModeProp ->
            let
                setVerboseWhenNeeded c l =
                    Lens.taking c traverse . _2 . l . Lens._Just %~ (setToVerbose >>)
                setToVerbose = (presModeProp ^. pSet) Sugar.Verbose & transaction
                orderOp x =
                    case presModeProp ^. pVal of
                    Sugar.Verbose -> x
                    Sugar.Operator l r ->
                        fields (== l) <> fields (== r) <> fields (`notElem` [l, r])
                    where
                        fields p = filter (p . (^. _2 . Sugar.piTag . Sugar.tagRefTag . Sugar.tagVal)) x
            in
            setVerboseWhenNeeded 3 Sugar.piMOrderBefore orig
            & setVerboseWhenNeeded 2 Sugar.piMOrderAfter
            & orderOp
