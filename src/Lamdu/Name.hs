{-# LANGUAGE TemplateHaskell #-}
module Lamdu.Name
    ( Stored, CollisionSuffix
    , Collision(..), _NoCollision, _Collision
    , visible
    , TagText(..), ttText, ttCollision
    , StoredName(..), snDisplayText, snTagCollision
    , Name(..), _AutoGenerated, _Stored
    , isValidText
    ) where

import qualified Control.Lens as Lens
import qualified Data.Char as Char
import qualified Data.Text as Text
import qualified Lamdu.CharClassification as Chars
import qualified Lamdu.I18N.Name as Texts
import           Lamdu.Precedence (HasPrecedence(..))

import           Lamdu.Prelude

type Stored = Text

type CollisionSuffix = Int

data Collision
    = NoCollision
    | Collision CollisionSuffix
    | UnknownCollision -- we have a collision but unknown suffix (inside hole result)
    deriving (Show, Generic, Eq)

data TagText = TagText
    { _ttText :: Text
    , _ttCollision :: Collision
    } deriving (Show, Generic, Eq)

data StoredName = StoredName
    { _snDisplayText :: TagText
    , _snTagCollision :: Collision
    } deriving (Generic, Eq)

data Name
    = AutoGenerated Text
    | Stored StoredName
    | Unnamed CollisionSuffix
    deriving (Generic, Eq)

visible ::
    (MonadReader env m, Has (Texts.Name Text) env) =>
    Name -> m (TagText, Collision)
visible (Stored (StoredName disp tagCollision)) = pure (disp, tagCollision)
visible (AutoGenerated name) = pure (TagText name NoCollision, NoCollision)
visible (Unnamed suffix) =
    Lens.view (has . Texts.unnamed) <&>
    \x -> (TagText x NoCollision, Collision suffix)

Lens.makeLenses ''StoredName
Lens.makeLenses ''TagText
Lens.makePrisms ''Collision
Lens.makePrisms ''Name

instance Show Name where
    show (AutoGenerated text) = unwords ["(AutoName", show text, ")"]
    show (Unnamed suffix) = unwords ["(Unnamed", show suffix, ")"]
    show (Stored (StoredName disp collision)) =
        unwords ["(StoredName", show disp, show collision, ")"]

instance HasPrecedence Name where
    precedence (Stored (StoredName disp _)) =
        disp ^? ttText . Lens.ix 0 . Lens.to precedence & fromMaybe 12
    precedence _ = 12

isValidText :: Text -> Bool
isValidText x =
    Text.all f x
    || Text.all (`elem` Chars.operator) x
    where
        f c = Char.isAlphaNum c || c == '_'
