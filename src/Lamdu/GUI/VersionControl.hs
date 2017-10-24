{-# LANGUAGE NoImplicitPrelude ,RecordWildCards, TypeOperators, OverloadedStrings, RankNTypes #-}
module Lamdu.GUI.VersionControl
    ( make
    ) where

import qualified Control.Lens as Lens
import qualified Data.List.Utils as ListUtils
import qualified Data.Store.Property as Property
import           Data.Store.Rev.Branch (Branch)
import qualified Data.Store.Rev.Branch as Branch
import           Data.Store.Transaction (Transaction)
import qualified Data.Store.Transaction as Transaction
import qualified GUI.Momentu.Align as Align
import           GUI.Momentu.EventMap (EventMap)
import qualified GUI.Momentu.EventMap as E
import           GUI.Momentu.MetaKey (MetaKey(..), noMods)
import qualified GUI.Momentu.MetaKey as MetaKey
import qualified GUI.Momentu.State as GuiState
import           GUI.Momentu.Widget (Widget)
import qualified GUI.Momentu.Widget as Widget
import qualified GUI.Momentu.Widgets.Choice as Choice
import qualified GUI.Momentu.Widgets.FocusDelegator as FocusDelegator
import qualified GUI.Momentu.Widgets.TextEdit as TextEdit
import qualified GUI.Momentu.Widgets.TextEdit.Property as TextEdits
import qualified Lamdu.Data.Anchors as Anchors
import qualified Lamdu.GUI.VersionControl.Config as VersionControl
import qualified Lamdu.GUI.WidgetIds as WidgetIds
import           Lamdu.VersionControl.Actions (Actions(..))

import           Lamdu.Prelude

branchNameFDConfig :: FocusDelegator.Config
branchNameFDConfig = FocusDelegator.Config
    { FocusDelegator.focusChildKeys = [MetaKey noMods MetaKey.Key'F2]
    , FocusDelegator.focusChildDoc = E.Doc ["Branches", "Rename"]
    , FocusDelegator.focusParentKeys = [MetaKey noMods MetaKey.Key'Enter]
    , FocusDelegator.focusParentDoc = E.Doc ["Branches", "Done renaming"]
    }

undoEventMap ::
    Functor m =>
    VersionControl.Config -> Maybe (m Widget.Id) ->
    EventMap (m GuiState.Update)
undoEventMap VersionControl.Config{..} =
    maybe mempty .
    Widget.keysEventMapMovesCursor undoKeys $ E.Doc ["Edit", "Undo"]

redoEventMap ::
    Functor m =>
    VersionControl.Config -> Maybe (m Widget.Id) ->
    EventMap (m GuiState.Update)
redoEventMap VersionControl.Config{..} =
    maybe mempty .
    Widget.keysEventMapMovesCursor redoKeys $ E.Doc ["Edit", "Redo"]

globalEventMap ::
    Applicative f =>
    VersionControl.Config -> Actions t f ->
    EventMap (f GuiState.Update)
globalEventMap VersionControl.Config{..} actions = mconcat
    [ Widget.keysEventMapMovesCursor makeBranchKeys
      (E.Doc ["Branches", "New"]) $ branchTextEditId <$> makeBranch actions
    , Widget.keysEventMapMovesCursor jumpToBranchesKeys
      (E.Doc ["Branches", "Select"]) $
      (pure . branchDelegatorId . currentBranch) actions
    , undoEventMap VersionControl.Config{..} $ mUndo actions
    , redoEventMap VersionControl.Config{..} $ mRedo actions
    ]

choiceWidgetConfig :: VersionControl.Config -> VersionControl.Theme -> Choice.Config
choiceWidgetConfig VersionControl.Config{..} VersionControl.Theme{..} =
    Choice.Config
    { Choice.cwcFDConfig =
        FocusDelegator.Config
        { FocusDelegator.focusChildKeys = [MetaKey noMods MetaKey.Key'Enter]
        , FocusDelegator.focusChildDoc = E.Doc ["Branches", "Select"]
        , FocusDelegator.focusParentKeys = [MetaKey noMods MetaKey.Key'Enter]
        , FocusDelegator.focusParentDoc = E.Doc ["Branches", "Choose selected"]
        }
    , Choice.cwcExpandMode = Choice.AutoExpand selectedBranchColor
    , Choice.cwcOrientation = Choice.Vertical
    }

branchDelegatorId :: Branch t -> Widget.Id
branchDelegatorId = WidgetIds.fromUUID . Branch.uuid

branchTextEditId :: Branch t -> Widget.Id
branchTextEditId = (`Widget.joinId` ["textedit"]) . branchDelegatorId

make ::
    (MonadReader env mr, GuiState.HasCursor env, TextEdit.HasStyle env,
     Applicative mw, Monad n) =>
    VersionControl.Config -> VersionControl.Theme ->
    (forall a. Transaction n a -> mw a) ->
    (forall a. Transaction n a -> mr a) ->
    Actions n mw ->
    (Widget (mw GuiState.Update) -> mr (Widget (mw GuiState.Update))) ->
    mr (Widget (mw GuiState.Update))
make VersionControl.Config{..} VersionControl.Theme{..} rwtransaction rtransaction actions mkWidget =
    do
        branchNameEdits <- branches actions & traverse makeBranchNameEdit
        branchSelector <-
            Choice.make ?? setCurrentBranch actions
            ?? branchNameEdits ?? currentBranch actions
            ?? choiceWidgetConfig VersionControl.Config{..} VersionControl.Theme{..}
            ?? WidgetIds.branchSelection
        mkWidget branchSelector
            <&> E.strongerEvents (globalEventMap VersionControl.Config{..} actions)
    where
        empty = TextEdit.EmptyStrings "unnamed branch" ""
        makeBranchNameEdit branch =
            do
                nameProp <-
                    Anchors.assocNameRef (Branch.uuid branch) ^. Transaction.mkProperty
                    & Lens.mapped . Property.pSet . Lens.mapped %~ rwtransaction
                    & rtransaction
                branchNameEdit <-
                    (FocusDelegator.make ?? branchNameFDConfig
                     ?? FocusDelegator.FocusEntryParent ?? branchDelegatorId branch
                    ) <*>
                    ( TextEdits.makeLineEdit ?? empty ?? nameProp ?? branchTextEditId branch
                      <&> (^. Align.tValue) )
                let delEventMap
                        | ListUtils.isLengthAtLeast 2 (branches actions) =
                            Widget.keysEventMapMovesCursor
                            delBranchKeys (E.Doc ["Branches", "Delete"])
                            (branchDelegatorId <$> deleteBranch actions branch)
                        | otherwise = mempty
                return (branch, E.weakerEvents delEventMap branchNameEdit)
