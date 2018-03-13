{-# LANGUAGE NoImplicitPrelude, LambdaCase #-}

module Main where

import           TestInstances ()

import qualified Control.Lens as Lens
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import           Data.Data.Lens (template)
import           Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map as Map
import           Data.Vector.Vector2 (Vector2(..))
import           GUI.Momentu.Align (Aligned(..))
import           GUI.Momentu.Animation (R)
import           GUI.Momentu.Draw (Color(..))
import qualified GUI.Momentu.Element as Element
import           GUI.Momentu.View (View(..))
import qualified GUI.Momentu.Widgets.GridView as GridView
import           Lamdu.Calc.Identifier (identHex)
import qualified Lamdu.Calc.Type.Scheme as Scheme
import qualified Lamdu.Calc.Val as V
import qualified Lamdu.Config.Sampler as ConfigSampler
import           Lamdu.Config.Theme (Theme)
import qualified Lamdu.Data.Export.JSON as JsonFormat
import qualified Lamdu.Data.Export.JSON.Codec as JsonCodec
import qualified Lamdu.Data.Definition as Def
import qualified Lamdu.Infer as Infer
import qualified Lamdu.Themes as Themes
import           System.FilePath (takeFileName)
import           Text.PrettyPrint.HughesPJClass (prettyShow)

import           Lamdu.Prelude
import           Test.Framework
import           Test.Framework.Providers.HUnit (testCase)
import           Test.Framework.Providers.QuickCheck2 (testProperty)
import           Test.HUnit

jsonCodecMigrationTest :: IO ()
jsonCodecMigrationTest = JsonFormat.fileImportAll "test/old-codec-factorial.json" & void

colorSchemeTest :: IO ()
colorSchemeTest = Themes.getFiles >>= traverse_ verifyTheme

colorSV :: Color -> (Double, Double)
colorSV (Color r g b _a) =
    (if v == 0 then 0 else (v - m) / v, v)
    where
        v = maximum [r, g, b]
        m = minimum [r, g, b]

colorSat :: Color -> Double
colorSat = fst . colorSV

roundIn :: RealFrac a => a -> a -> a
roundIn unit x = fromIntegral (round (x / unit) :: Integer) * unit

verifyTheme :: FilePath -> IO ()
verifyTheme filename =
    ConfigSampler.readJson filename >>= verify
    where
        verify :: Theme -> IO ()
        verify theme
            | "retro.json" == takeFileName filename = traverse_ verifyRetroColor colors
            | Map.size saturations <= 3 = pure ()
            | otherwise =
                assertString
                ("Too many saturation options in theme " ++ filename ++ ":\n" ++
                prettyShow (Map.toList saturations))
            where
                saturations =
                    colors <&> (\c -> (roundIn 0.001 (colorSat c), [c]))
                    & Map.fromListWith (++)
                colors = theme ^.. template
        verifyRetroColor col@(Color r g b a)
            | all (`elem` [0, 0.5, 1.0]) [r, g, b]
                && elem a [0, 0.05, 0.1, 0.5, 1.0] = pure ()
            | otherwise =
                assertString ("Bad retro color in theme " ++ filename ++ ": " ++ show col)

verifyNoBrokenDefsTest :: IO ()
verifyNoBrokenDefsTest =
    LBS.readFile "freshdb.json" <&> Aeson.eitherDecode
    >>= either fail pure
    <&> Aeson.fromJSON
    >>= \case
        Aeson.Error str -> fail str
        Aeson.Success x ->
            x >>= (^.. JsonCodec._EntityDef)
            <&> Def.defPayload %~ (^. Lens._3)
            & verifyDefs

verifyDefs :: [Def.Definition v V.Var] -> IO ()
verifyDefs defs =
    defs ^.. traverse . Def.defBody . Def._BodyExpr . Def.exprFrozenDeps . Infer.depsGlobalTypes
    <&> Map.toList & concat
    & traverse_ (uncurry verifyGlobalType)
    where
        defTypes = defs <&> (\x -> (x ^. Def.defPayload, x ^. Def.defType)) & Map.fromList
        verifyGlobalType var typ =
            case defTypes ^. Lens.at var of
            Nothing -> assertString ("Missing def referred in frozen deps: " ++ showVar)
            Just x
                | Scheme.alphaEq x typ -> pure ()
                | otherwise ->
                    assertString
                    ("Frozen def type mismatch for " ++ showVar ++ ":\n" ++
                    prettyShow x ++ "\nvs\n" ++ prettyShow typ)
            where
                showVar = V.vvName var & identHex

propGridSensibleSize :: NonEmpty (NonEmpty (Vector2 R, Vector2 R)) -> Bool
propGridSensibleSize viewConfs =
    grid ^. Element.width >= minWidth && grid ^. Element.height >= minHeight
    where
        minWidth = sum colWidths * 0.999 -- Due to float inaccuracies
        minHeight = sum rowHeights * 0.999 -- Due to float inaccuracies
        colWidths =
            views <&> Lens.mapped %~ (^. Element.width)
            & foldl1 (NonEmpty.zipWith max)
        rowHeights = views <&> Lens.mapped %~ (^. Element.height) <&> maximum
        views = viewsFromConf viewConfs
        grid = GridView.make views

viewsFromConf :: NonEmpty (NonEmpty (Vector2 R, Vector2 R)) -> NonEmpty (NonEmpty (Aligned View))
viewsFromConf viewConfs =
    viewConfs <&> onTail (take minRowTailLen) <&> Lens.mapped %~ mkView
    where
        minRowTailLen = minimum (viewConfs ^.. traverse <&> NonEmpty.tail <&> length)
        mkView (al, sz) =
            Aligned (al - (al <&> floor <&> (fromIntegral :: Integer -> R)))
            (View sz mempty)
        onTail f (x :| xs) = x :| f xs

main :: IO ()
main =
    defaultMainWithOpts
    [ testCase "json-codec-migration" jsonCodecMigrationTest
    , testCase "color-scheme" colorSchemeTest
    , testCase "no-broken-defs" verifyNoBrokenDefsTest
    , testProperty "grid-sensible-size" propGridSensibleSize
    ] mempty
