module Tests.Wytiwys (test) where

import           Control.Monad.Once (OnceT, evalOnceT)
import           GUI.Momentu (Key, noMods, shift)
import           GUI.Momentu.EventMap (Event(..))
import qualified Graphics.UI.GLFW as GLFW
import           Lamdu.Data.Db.Layout (ViewM, runDbTransaction)
import qualified Lamdu.Data.Db.Layout as DbLayout
import qualified Lamdu.Data.Export.JS as ExportJS
import qualified Lamdu.Data.Ops as DataOps
import           Lamdu.Expr.IRef (globalId)
import           Lamdu.VersionControl (runAction)
import qualified Revision.Deltum.Transaction as Transaction
import           Test.Lamdu.Db (ramDB)
import qualified Test.Lamdu.Env as Env
import           Test.Lamdu.Exec (runJS)
import           Test.Lamdu.Gui
import           Test.Lamdu.Instances ()
import qualified Test.Tasty as Tasty

import           Test.Lamdu.Prelude

charKey :: Char -> Maybe Key
charKey ' ' = Just GLFW.Key'Space
charKey '\n' = Just GLFW.Key'Enter
charKey '\t' = Just GLFW.Key'Tab
charKey ',' = Just GLFW.Key'Comma
charKey '⌫' = Just GLFW.Key'Backspace
charKey '→' = Just GLFW.Key'Right
charKey '↑' = Just GLFW.Key'Up
charKey '↓' = Just GLFW.Key'Down
charKey '←' = Just GLFW.Key'Left
charKey _ = Nothing

charEvent :: Char -> Event
charEvent '«' = shift GLFW.Key'Left & simpleKeyEvent
charEvent x = charKey x & maybe (EventChar x) (simpleKeyEvent . noMods)

applyActions :: HasCallStack => Env.Env -> String -> OnceT (T ViewM) Env.Env
applyActions startEnv xs =
    go (zip [0..] xs) startEnv
    where
        go [] env  = pure env
        go ((_,'✗'):(i,x):rest) env =
            do
                eventShouldDoNothing (take (i+1) xs) dummyVirt (charEvent x) env
                go rest env
        go ((i,x):rest) env =
            applyEventWith (take (i+1) xs) dummyVirt (charEvent x) env >>= go rest

wytiwysCompile :: HasCallStack => IO (Transaction.Store DbLayout.DbM) -> String -> IO String
wytiwysCompile mkDb src =
    do
        env <- Env.make
        db <- mkDb
        do
            repl <- DataOps.newEmptyPublicDefinitionWithPane DbLayout.codeAnchors & lift
            _ <- applyActions env src
            globalId repl & ExportJS.compile & lift
            & evalOnceT
            & runAction
            & runDbTransaction db

wytiwysDb :: HasCallStack => IO (Transaction.Store DbLayout.DbM) -> String -> ByteString -> TestTree
wytiwysDb mkDb src result =
    wytiwysCompile mkDb src
    >>= runJS
    >>= assertEqual "Expected output" (result <> "\n")
    & testCase (show src)

test :: HasCallStack => TestTree
test =
    Tasty.withResource (ramDB ["data/freshdb.json"]) mempty $
    \mkDb ->
    let wytiwys = wytiwysDb (join mkDb)
    in
    testGroup "WYTIWYS"
    [ wytiwys "1+1" "2"

    , wytiwys "2*3+4" "10"
    , wytiwys "2*(3+4)" "14"
    , wytiwys "2*(3+4" "14" -- Don't have to close paren

    , wytiwys "sum (1..10)" "45" -- Debatable issue: Space is necessary here!
    , wytiwys "sum 1..10" "45" -- An Ergonomic WYTIWIS violation: types cause fragment
    , wytiwys "sum 1..10.map n*2" "90"
    , wytiwys "sum 1..10.map 2*num\n" "90" -- TODO: Would be better without requiring the enter at the end
    , wytiwys "sum 1..10.map 2*(num+1)" "108"
    , wytiwys "sum 1..10.map 2*(num+1" "108"

    , wytiwys "if 1=2:3\t4" "4" -- Type if-expressions without "else:"

    , wytiwys "sum 1..10.filter nu>5" "30"
    , wytiwys "sum 1..10.filter n>5" "30"
    , wytiwys "sum 1..10.filter 12<(num+1)*12" "45"

    , wytiwys "if {={:1\t2" "1" -- "{" expands to "{}"
    , wytiwys "let {val 1\trec.val\n" "1" -- "let " jumps straight to value of let

    , wytiwys "1..10.sort lhs>rhs))@ 2" "7" -- Close parens get out of lambda

    , wytiwys "{a 7,b 5}.a\n" "7"
    , wytiwys "{a 7,b 5}.a+2" "9"

    , wytiwys "if ⌫1+2" "3" -- Backspace after "if " deletes it

    , wytiwys "7+negate\n→4" "3"
    , wytiwys "1==2««if 3\t4" "4"

    , wytiwys "if 'a'=='b'\t1\t2" "2"

    , wytiwys "===↑↓⌫⌫⌫1" "1"

    , wytiwys "if 'a=='a\n←←id\t3\t4" "3"

    , wytiwys "toArr repli 3000\t0««.len\n" "3000"

    , wytiwys "1+↑✗2↓2" "3" -- When cursor is at fragment's search term the should "2" do nothing.
    ]
