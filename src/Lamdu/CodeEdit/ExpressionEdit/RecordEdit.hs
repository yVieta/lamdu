{-# LANGUAGE OverloadedStrings #-}
module Lamdu.CodeEdit.ExpressionEdit.RecordEdit(make) where

import Control.Applicative ((<$>), (<*>), (*>))
import Control.Lens.Operators
import Control.MonadA (MonadA)
import Data.Monoid (Monoid(..))
import Data.Store.Transaction (Transaction)
import Data.Vector.Vector2 (Vector2(..))
import Lamdu.CodeEdit.ExpressionEdit.ExpressionGui (ExpressionGui)
import Lamdu.CodeEdit.ExpressionEdit.ExpressionGui.Monad (ExprGuiM)
import Lamdu.Config (Config)
import qualified Control.Lens as Lens
import qualified Graphics.UI.Bottle.EventMap as E
import qualified Graphics.UI.Bottle.Widget as Widget
import qualified Graphics.UI.Bottle.Widgets.Box as Box
import qualified Graphics.UI.Bottle.Widgets.Grid as Grid
import qualified Lamdu.BottleWidgets as BWidgets
import qualified Lamdu.CodeEdit.ExpressionEdit.ExpressionGui as ExpressionGui
import qualified Lamdu.CodeEdit.ExpressionEdit.ExpressionGui.Monad as ExprGuiM
import qualified Lamdu.CodeEdit.Sugar as Sugar
import qualified Lamdu.Config as Config
import qualified Lamdu.WidgetEnvT as WE
import qualified Lamdu.WidgetIds as WidgetIds

type T = Transaction

make ::
  MonadA m =>
  Sugar.Record m (Sugar.ExpressionN m) -> Widget.Id -> ExprGuiM m (ExpressionGui m)
make = ExpressionGui.wrapExpression . makeUnwrapped

makeUnwrapped ::
  MonadA m =>
  Sugar.Record m (Sugar.ExpressionN m) -> Widget.Id -> ExprGuiM m (ExpressionGui m)
makeUnwrapped (Sugar.Record k (Sugar.FieldList fields mAddField)) myId =
  ExprGuiM.assignCursor myId bracketId $ do
    config <- ExprGuiM.widgetEnv WE.readConfig
    let
      makeFieldRow (Sugar.RecordField mItemActions tagExpr fieldExpr) = do
        ((fieldRefGui, fieldExprGui), resultPickers) <-
          ExprGuiM.listenResultPickers $
          (,)
          <$> ExprGuiM.makeSubexpresion 0 tagExpr
          <*> ExprGuiM.makeSubexpresion 0 fieldExpr
        let
          itemEventMap = maybe mempty (recordItemEventMap config resultPickers) mItemActions
          space = ExpressionGui.fromValueWidget BWidgets.stdSpaceWidget
        return . ExpressionGui.makeRow $
          [(1, scaleTag fieldRefGui), (0.5, space), (0, fieldExprGui)]
          & Lens.mapped . Lens._2 . ExpressionGui.egWidget %~
            Widget.weakerEvents itemEventMap
      scaleTag =
        ExpressionGui.egWidget %~
        Widget.scale (realToFrac <$> Config.fieldTagScaleFactor config)
    fieldRows <- mapM makeFieldRow fields
    let
      fieldsWidget = Grid.toWidget $ Grid.make fieldRows
      mkBracketView text =
        ExprGuiM.withFgColor (parensColor k config) . ExprGuiM.widgetEnv .
        BWidgets.makeLabel text $ Widget.toAnimId myId
    openBracketWidget <-
      ExprGuiM.widgetEnv . BWidgets.makeFocusableView bracketId =<<
      mkBracketView "{"
    closeBracketWidget <- mkBracketView "}"
    let
      height = Widget.wSize . Lens._2
      fieldsHeight = fieldsWidget ^. height
      resizedBracket widget
        | fieldsHeight > 0 =
          Widget.scale (Vector2 1 (fieldsHeight / widget ^. height)) widget
        | otherwise = widget
    let
      eventMap =
        mkEventMap (fmap WidgetIds.fromGuid)
        mAddField (Config.recordAddFieldKeys config) $
        E.Doc ["Edit", "Record", "Add First Field"]
    return . ExpressionGui.fromValueWidget . Widget.weakerEvents eventMap $
      Box.hboxCentered
      [ resizedBracket openBracketWidget
      , fieldsWidget
      , resizedBracket closeBracketWidget
      ]
  where
    parensColor Sugar.Type = Config.recordTypeParensColor
    parensColor Sugar.Val = Config.recordValParensColor
    bracketId = Widget.joinId myId ["{"]
    mkEventMap f mAction keys doc =
      maybe mempty (Widget.keysEventMapMovesCursor keys doc . f) mAction

recordItemEventMap ::
  MonadA m => Config -> [T m ()] -> Sugar.ListItemActions m -> Widget.EventHandlers (T m)
recordItemEventMap config resultPickers (Sugar.ListItemActions addNext delete) =
  mconcat
  [ Widget.keysEventMapMovesCursor (Config.recordAddFieldKeys config)
    (E.Doc ["Edit", "Record", "Add Next Field"]) $ WidgetIds.fromGuid <$> (sequence_ resultPickers *> addNext)
  , Widget.keysEventMapMovesCursor (Config.delKeys config)
    (E.Doc ["Edit", "Record", "Delete Field"]) $ WidgetIds.fromGuid <$> delete
  ]
