{-# OPTIONS -O0 #-}
{-# LANGUAGE TemplateHaskell, FlexibleInstances, DerivingVia, RankNTypes #-}
module Lamdu.I18N.Texts where

import qualified Control.Lens as Lens
import qualified Data.Aeson.TH.Extended as JsonTH
import qualified GUI.Momentu.Direction as Dir
import qualified GUI.Momentu.EventMap as EventMap
import qualified GUI.Momentu.Glue as Glue
import qualified GUI.Momentu.Main as MainLoop
import qualified GUI.Momentu.Widgets.Choice as Choice
import qualified GUI.Momentu.Widgets.Grid as Grid
import qualified GUI.Momentu.Widgets.Menu as Menu
import qualified GUI.Momentu.Widgets.Menu.Search as SearchMenu
import qualified GUI.Momentu.Widgets.TextEdit as TextEdit
import qualified GUI.Momentu.Zoom as Zoom
import           Lamdu.Config.Folder (HasConfigFolder(..))
import           Lamdu.Data.Tag (HasLanguageIdentifier(..))
import           Lamdu.Name (HasNameTexts(..), NameTexts)

import           Lamdu.Prelude

data Code a = Code
    { _assign :: a -- Assignment
    , _relay :: a -- Apply
    , _let_ :: a
    , _toNom :: a
    , _fromNom :: a
    , _repl :: a
    , -- Case
      _case_ :: a
    , _of_ :: a
    , _absurd :: a
    , -- If:
      _if_ :: a
    , _condColon :: a -- Colon after if's condition
    , _else_ :: a
    , _elseShort :: a -- "el" in "elif"
    , -- Inject
      _inject :: a
    , _nullaryInject :: a
    , -- Getvar
      _paramsRecordOpener :: a
    , _paramsRecordCloser :: a
    , -- Lambda:
      _defer :: a
    , _lam :: a
    , _arrow :: a
    , -- Literal a:
      _textOpener :: a
    , _textCloser :: a
    , -- Record:
      _recordOpener :: a
    , _recordSep :: a
    , _recordCloser :: a
    }
    deriving stock (Generic, Generic1, Eq, Functor, Foldable, Traversable)
    deriving Applicative via (Generically1 Code)
Lens.makeLenses ''Code
JsonTH.derivePrefixed "_" ''Code

data Collaboration a = Collaboration
    { _collaboration :: a
    , _exportDefToJSON :: a
    , _exportEverythingToJSON :: a
    , _exportReplToJSON :: a
    , _exportReplToJS :: a
    , _importJSON :: a
    , _importReplFromJSON :: a
    }
    deriving stock (Generic, Generic1, Eq, Functor, Foldable, Traversable)
    deriving Applicative via (Generically1 Collaboration)
Lens.makeLenses ''Collaboration
JsonTH.derivePrefixed "_" ''Collaboration

data Definitions a = Definitions
    { _newDefinitionButton :: a
    , _newDefinition :: a
    , _undelete :: a
    , _undeleteButton :: a
    , _defUpdateHeader :: a
    , _defUpdateTo :: a
    , _defUpdateWas :: a
    , _def :: a
    , _extractReplToDef :: a
    , _execRepl :: a
    , _extract :: a
    }
    deriving stock (Generic, Generic1, Eq, Functor, Foldable, Traversable)
    deriving Applicative via (Generically1 Definitions)
Lens.makeLenses ''Definitions
JsonTH.derivePrefixed "_" ''Definitions

data Navigation a = Navigation
    { _jumpToError :: a
    , _goto :: a
    , _goBack :: a
    , _nextEntry :: a
    , _enterSubexpression :: a
    , _leaveSubexpression :: a
    }
    deriving stock (Generic, Generic1, Eq, Functor, Foldable, Traversable)
    deriving Applicative via (Generically1 Navigation)
Lens.makeLenses ''Navigation
JsonTH.derivePrefixed "_" ''Navigation

data CodeUI a = CodeUI
    { _hidden :: a
    , _shown :: a
    , _pick :: a
    , _new :: a
    , _select :: a
    , _delete :: a
    , _rename :: a
    , _doneRenaming :: a
    , _pane :: a
    , _close :: a
    , _moveDown :: a
    , _moveUp :: a
    , _presentationMode :: a
    , _pModeVerbose :: a
    , _pModeOO :: a
    , _pModeInfix :: a
    , _jsException :: a
    , _jsReachedAHole :: a
    , _jsStaleDep :: a
    , _jsUnhandledCase :: a
    , _transform :: a
    , _replace :: a
    , _replaceParent :: a
    , _applyOperator :: a
    , _add :: a
    , _letClause :: a
    , _modify :: a
    , _detach :: a
    , _literal :: a
    , _literalText :: a
    , _literalNumber :: a
    , _startEditing :: a
    , _stopEditing :: a
    , _setToHole :: a
    , _negate :: a
    , _value :: a
    }
    deriving stock (Generic, Generic1, Eq, Functor, Foldable, Traversable)
    deriving Applicative via (Generically1 CodeUI)
Lens.makeLenses ''CodeUI
JsonTH.derivePrefixed "_" ''CodeUI

data StatusBar a = StatusBar
    { _sbStatusBar :: a
    , _sbAnnotations :: a
    , _sbEvaluation :: a
    , _sbTypes :: a
    , _sbNone :: a
    , _sbSwitchAnnotations :: a
    , _sbBranch :: a
    , _sbSwitchHelp :: a
    , _sbHelp :: a
    , _sbLanguage :: a
    , _sbSwitchLanguage :: a
    , _sbTheme :: a
    , _sbSwitchTheme :: a
    }
    deriving stock (Generic, Generic1, Eq, Functor, Foldable, Traversable)
    deriving Applicative via (Generically1 StatusBar)
Lens.makeLenses ''StatusBar
JsonTH.derivePrefixed "_sb" ''StatusBar

data Versioning a = Versioning
    { _branches :: a
    , _undo :: a
    , _redo :: a
    }
    deriving stock (Generic, Generic1, Eq, Functor, Foldable, Traversable)
    deriving Applicative via (Generically1 Versioning)
JsonTH.derivePrefixed "_" ''Versioning
Lens.makeLenses ''Versioning

data Texts a = Texts
    { _code :: Code a
    , _codeUI :: CodeUI a
    , _collaborationTexts :: Collaboration a
    , _navigationTexts :: Navigation a
    , _definitions :: Definitions a
    , _name :: NameTexts a
    , _statusBar :: StatusBar a
    , _versioning :: Versioning a
    , _dir :: Dir.Texts a
    , _glue :: Glue.Texts a
    , _menu :: Menu.Texts a
    , _searchMenu :: SearchMenu.Texts a
    , _grid :: Grid.Texts a
    , _eventMap :: EventMap.Texts a
    , _choice :: Choice.Texts a
    , _textEdit :: TextEdit.Texts a
    , _zoom :: Zoom.Texts a
    , _mainLoop :: MainLoop.Texts a
    }
    deriving stock (Generic, Generic1, Eq, Functor, Foldable, Traversable)
    deriving Applicative via (Generically1 Texts)
-- Get-field's dot is currently omitted from the symbols,
-- because it has special disambiguation logic implemented in the dotter etc.

Lens.makeLenses ''Texts
JsonTH.derivePrefixed "_" ''Texts

data Language = Language
    { _lDirection :: Dir.Layout
    , _lIdentifier :: Text
    , _lTexts :: Texts Text
    } deriving (Eq)

Lens.makeLenses ''Language
JsonTH.derivePrefixed "_l" ''Language

instance HasConfigFolder Language where
    configFolder _ = "languages"

class
    ( Glue.HasTexts env, Dir.HasTexts env, Choice.HasTexts env
    , TextEdit.HasTexts env, Grid.HasTexts env, HasNameTexts env
    , Menu.HasTexts env, SearchMenu.HasTexts env, HasLanguageIdentifier env
    ) => HasLanguage env where
    language :: Lens' env Language
instance EventMap.HasTexts Language where texts = lTexts . eventMap

instance Dir.HasLayoutDir Language where layoutDir = lDirection
instance Dir.HasTexts Language where texts = lTexts . dir
instance Glue.HasTexts Language where texts = lTexts . glue
instance Menu.HasTexts Language where texts = lTexts . menu
instance SearchMenu.HasTexts Language where texts = lTexts . searchMenu
instance Grid.HasTexts Language where texts = lTexts . grid
instance Choice.HasTexts Language where texts = lTexts . choice
instance TextEdit.HasTexts Language where texts = lTexts . textEdit
instance MainLoop.HasTexts Language where texts = lTexts . mainLoop
instance HasNameTexts Language where nameTexts = lTexts . name
instance HasLanguageIdentifier Language where languageIdentifier = lIdentifier
instance HasLanguage Language where language = id
instance Zoom.HasTexts Language where texts = lTexts . zoom

texts :: HasLanguage env => Lens' env (Texts Text)
texts = language . lTexts

quit :: HasLanguage env => Lens' env Text
quit = language . MainLoop.texts . MainLoop.textQuit

edit :: HasLanguage env => Lens' env Text
edit = language . TextEdit.texts . TextEdit.textEdit

view :: HasLanguage env => Lens' env Text
view = language . Zoom.texts . Zoom.view

navigation :: HasLanguage env => Lens' env Text
navigation = language . Dir.texts . Dir.navigation
