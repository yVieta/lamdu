{-# LANGUAGE TypeApplications, FlexibleInstances, KindSignatures, MultiParamTypeClasses, DataKinds, DefaultSignatures #-}
module Lamdu.Sugar.Lens
    ( SugarExpr(..)
    , childPayloads
    , bodyUnfinished
    , defSchemes
    , assignmentBodyAddFirstParam
    , binderFuncParamActions
    , binderResultExpr
    , holeTransformExprs, holeOptionTransformExprs
    , annotationTypes
    , getVarName
    ) where

import           AST (Tree, KNodes(..), KTraversable(..), (#>))
import qualified AST
import           AST.Knot.Ann (Ann(..), ann, val)
import qualified Control.Lens as Lens
import           Data.Constraint (Dict(..))
import           Data.Proxy (Proxy(..))
import           Lamdu.Sugar.Types

import           Lamdu.Prelude

childPayloads ::
    KTraversable expr =>
    Lens.Traversal' (Tree expr (Ann a)) a
childPayloads f =
    AST.traverseK (const (ann f))

class KTraversable t => SugarExpr t where
    isUnfinished :: t f -> Bool
    isUnfinished _ = False

    isForbiddenInLightLam :: t f -> Bool
    isForbiddenInLightLam = isUnfinished

    sugarExprRecursive ::
        Proxy t -> Dict (KNodesConstraint t SugarExpr)
    default sugarExprRecursive ::
        KNodesConstraint t SugarExpr =>
        Proxy t -> Dict (KNodesConstraint t SugarExpr)
    sugarExprRecursive _ = Dict

instance AST.Recursive SugarExpr where
    recurse =
        sugarExprRecursive . p
        where
            p :: Proxy (SugarExpr k) -> Proxy k
            p _ = Proxy

instance SugarExpr (Const (GetVar name o))
instance SugarExpr (Const (NullaryVal name i o))

instance SugarExpr (Const (BinderVarRef name o)) where
    isUnfinished (Const x) = Lens.has binderVarRefUnfinished x

instance SugarExpr (Assignment name i o) where
    isUnfinished (BodyPlain x) = isUnfinished (x ^. apBody)
    isUnfinished BodyFunction{} = False

instance SugarExpr (Else name i o) where
    isUnfinished (SimpleElse x) = isUnfinished x
    isUnfinished ElseIf{} = False

instance SugarExpr (Function name i o) where
    isForbiddenInLightLam = Lens.has (fParams . _Params)

instance SugarExpr (Binder name i o) where
    isUnfinished (BinderExpr x) = isUnfinished x
    isUnfinished BinderLet{} = False
    isForbiddenInLightLam BinderLet{} = True
    isForbiddenInLightLam (BinderExpr x) = isForbiddenInLightLam x

instance SugarExpr (Body name i o) where
    isUnfinished BodyHole{} = True
    isUnfinished BodyFragment{} = True
    isUnfinished (BodyGetVar (GetBinder x)) = isUnfinished (Const x)
    isUnfinished _ = False
    isForbiddenInLightLam (BodyLam f) = isForbiddenInLightLam (f ^. lamFunc)
    isForbiddenInLightLam x = isUnfinished x

binderVarRefUnfinished :: Lens.Traversal' (BinderVarRef name m) ()
binderVarRefUnfinished =
    bvForm . _GetDefinition . Lens.failing _DefDeleted (_DefTypeChanged . Lens.united)

bodyUnfinished :: Lens.Traversal' (Tree (Body name i o) (Ann a)) ()
bodyUnfinished =
    _BodyHole . Lens.united
    & Lens.failing (_BodyFragment . Lens.united)
    & Lens.failing (_BodyGetVar . _GetBinder . binderVarRefUnfinished)
    & Lens.failing (_BodyLabeledApply . aFunc . val . Lens._Wrapped . binderVarRefUnfinished)

defBodySchemes :: Lens.Traversal' (DefinitionBody name i o expr) (Scheme name)
defBodySchemes f (DefinitionBodyBuiltin b) =
    b & biType %%~ f
    <&> DefinitionBodyBuiltin
defBodySchemes f (DefinitionBodyExpression de) =
    de & deType %%~ f
    <&> DefinitionBodyExpression

defSchemes :: Lens.Traversal' (Definition name i o expr) (Scheme name)
defSchemes = drBody . defBodySchemes

binderFuncParamActions ::
    Lens.Traversal' (BinderParams name i o) (FuncParamActions name i o)
binderFuncParamActions _ (NullParam a) = pure (NullParam a)
binderFuncParamActions f (Params ps) = (traverse . fpInfo . piActions) f ps <&> Params

binderResultExpr ::
    Lens.IndexedLens' (Tree (Body name i o) (Ann ()))
    (Tree (Ann a) (Binder name i o)) a
binderResultExpr f (Ann pl x) =
    case x of
    BinderExpr e ->
        Lens.indexed f
        (AST.mapK (Proxy @AST.RTraversable #> AST.annotations .~ ()) e)
        pl
        <&> (`Ann` x)
    BinderLet l ->
        lBody (binderResultExpr f) l
        <&> BinderLet
        <&> Ann pl

holeOptionTransformExprs ::
    Monad i =>
    (Tree (Ann (Payload n0 i o ())) (Binder n0 i o) ->
        i (Tree (Ann (Payload n1 i o ())) (Binder n1 i o))) ->
    HoleOption n0 i o -> HoleOption n1 i o
holeOptionTransformExprs onExpr option =
    option
    { _hoSugaredBaseExpr = option ^. hoSugaredBaseExpr >>= onExpr
    , _hoResults = option ^. hoResults <&> Lens._2 %~ (>>= holeResultConverted onExpr)
    }

holeTransformExprs ::
    Monad i =>
    (Tree (Ann (Payload n0 i o ())) (Binder n0 i o) ->
        i (Tree (Ann (Payload n1 i o ())) (Binder n1 i o))) ->
    Hole n0 i o -> Hole n1 i o
holeTransformExprs onExpr =
    holeOptions . Lens.mapped . traverse %~ holeOptionTransformExprs onExpr

assignmentBodyAddFirstParam :: Lens' (Assignment name i o a) (AddFirstParam name i o)
assignmentBodyAddFirstParam f (BodyFunction x) = fAddFirstParam f x <&> BodyFunction
assignmentBodyAddFirstParam f (BodyPlain x) = apAddFirstParam f x <&> BodyPlain

annotationTypes :: Lens.Traversal' (Annotation name i) (Tree (Ann EntityId) (Type name))
annotationTypes _ AnnotationNone = pure AnnotationNone
annotationTypes f (AnnotationType x) = f x <&> AnnotationType
annotationTypes f (AnnotationVal x) = (annotationType . Lens._Just) f x <&> AnnotationVal

getVarName :: Lens.Traversal' (GetVar a o) a
getVarName f (GetParam x) = (pNameRef . nrName) f x <&> GetParam
getVarName f (GetBinder x) = (bvNameRef . nrName) f x <&> GetBinder
getVarName _ (GetParamsRecord x) = GetParamsRecord x & pure
