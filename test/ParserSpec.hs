{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Either (isLeft)
import Data.Text qualified as T
import Data.Time (fromGregorian)
import Test.Hspec

import MindGoblin.Parser
import MindGoblin.Types

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "Bullet Recognition (TEST_SPEC.md#1.1)" $ do
        it "parses open task bullet - user types . for todo" $ do
            -- Data flow: "." -> lexer -> Open bullet
            parseBullet "." `shouldBe` Right Open

        it "parses completed bullet - user types x for done" $ do
            -- Data flow: "x" -> lexer -> Completed bullet
            parseBullet "x" `shouldBe` Right Completed

        it "parses migrated bullet - user uses > for moved tasks" $ do
            parseBullet ">" `shouldBe` Right Migrated

        it "parses scheduled bullet - user uses < for timed items" $ do
            parseBullet "<" `shouldBe` Right Scheduled

        it "parses note bullet - user uses - for notes" $ do
            parseBullet "-" `shouldBe` Right Note

        it "parses priority bullet - user uses ! for urgent" $ do
            parseBullet "!" `shouldBe` Right Priority

        it "parses idea bullet - user uses * for ideas" $ do
            parseBullet "*" `shouldBe` Right Idea

        it "parses event bullet - user uses o for events" $ do
            parseBullet "o" `shouldBe` Right Event

        it "rejects invalid bullet character" $ do
            isLeft (parseBullet "#") `shouldBe` True

    describe "Task Parsing (TEST_SPEC.md#1.2)" $ do
        it "parses single-line task" $ do
            -- User story: "I write a simple task on one line"
            let input = ". Buy milk"
            case parseTaskLine (fromGregorian 2025 8 16) input of
                Right task -> do
                    taskBullet task `shouldBe` Open
                    taskText task `shouldBe` "Buy milk"
                    taskContexts task `shouldBe` []
                    taskDue task `shouldBe` Nothing
                    taskNotes task `shouldBe` []
                    taskUid task `shouldBe` Nothing
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "parses task with single context" $ do
            -- User story: "I add @store to remember where to do this task"
            let input = ". Buy milk @store"
            case parseTaskLine (fromGregorian 2025 8 16) input of
                Right task -> taskContexts task `shouldBe` [Context "store"]
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "parses task with multiple contexts" $ do
            -- User story: "I tag tasks with multiple contexts"
            let input = ". Call Bob @calls @urgent"
            case parseTaskLine (fromGregorian 2025 8 16) input of
                Right task -> taskContexts task `shouldBe` [Context "calls", Context "urgent"]
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "parses task with due date" $ do
            -- User story: "I add Due: dates to track deadlines"
            let input = ". Submit report Due: 2025-08-20"
            case parseTaskLine (fromGregorian 2025 8 16) input of
                Right task -> taskDue task `shouldBe` Just (fromGregorian 2025 8 20)
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "ignores freeform notes - documentation only" $ do
            -- User story: "Non-bulleted text is documentation only, not synced"
            -- @test-spec: TEST_SPEC.md#1.2-freeform-ignored
            let input = "Some documentation text"
            case parseTaskLine (fromGregorian 2025 8 16) input of
                Left _ -> return () -- Expected: parse should fail/ignore
                Right task -> expectationFailure $ "Should not create task for freeform text: " ++ show task

        it "parses mixed bullets and freeform" $ do
            -- User story: "Only bulleted items become tasks, freeform preserved but ignored"
            -- @test-spec: TEST_SPEC.md#1.2-mixed-content
            let input = "2025-08-16\n. Buy milk\nNotes about shopping\n. Call mom"
            case parseDateSection input of
                Right section -> do
                    length (sectionEntries section) `shouldBe` 2
                    map taskText (sectionEntries section) `shouldBe` ["Buy milk", "Call mom"]
                Left err -> expectationFailure $ "Parse failed: " ++ show err

    describe "Date Section Parsing (TEST_SPEC.md#1.3)" $ do
        it "parses valid date header" $ do
            -- User story: "I start each day with YYYY-MM-DD format"
            let input = "2025-08-16\n. Task"
            case parseDateSection input of
                Right section -> do
                    sectionDate section `shouldBe` fromGregorian 2025 8 16
                    length (sectionEntries section) `shouldBe` 1
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "rejects invalid date format" $ do
            -- User story: "System enforces consistent date format"
            let input = "08/16/2025\n. Task"
            isLeft (parseDateSection input) `shouldBe` True

        it "rejects invalid date values" $ do
            -- User story: "System validates date values are realistic"
            let input1 = "2025-13-45\n. Task" -- Invalid month and day
            let input2 = "2025-02-30\n. Task" -- Invalid day for February
            isLeft (parseDateSection input1) `shouldBe` True
            isLeft (parseDateSection input2) `shouldBe` True

        it "parses multiple date sections" $ do
            -- User story: "My file contains many days of tasks"
            let input = "2025-08-16\n. Task 1\n\n2025-08-17\n. Task 2"
            case parseTodoFile input of
                Right sections -> length sections `shouldBe` 2
                Left err -> expectationFailure $ "Parse failed: " ++ show err

    describe "Context Extraction (TEST_SPEC.md#1.4)" $ do
        it "extracts context at end of line" $ do
            -- User story: "I add @computer to tasks"
            extractContexts "Task @computer" `shouldBe` [Context "computer"]

        it "ignores @ in middle of words (like emails)" $ do
            -- User story: "Email addresses aren't contexts"
            extractContexts "Email bob@example.com" `shouldBe` []

        it "extracts multiple contexts" $ do
            extractContexts "Task @home @urgent @computer"
                `shouldBe` [Context "home", Context "urgent", Context "computer"]

        it "handles contexts with hyphens and underscores" $ do
            extractContexts "Task @home-office @high_priority"
                `shouldBe` [Context "home-office", Context "high_priority"]

    describe "Due Date Parsing (TEST_SPEC.md#1.5)" $ do
        it "parses valid due date" $ do
            -- User story: "I mark deadlines with Due: YYYY-MM-DD"
            parseDueDate "Due: 2025-08-20" `shouldBe` Just (fromGregorian 2025 8 20)

        it "ignores time in due date" $ do
            -- User story: "Times are ignored, we only track dates"
            parseDueDate "Due: 2025-08-20 14:30" `shouldBe` Just (fromGregorian 2025 8 20)

        it "returns Nothing for invalid format" $ do
            -- User story: "Natural language dates aren't supported (yet)"
            parseDueDate "Due: tomorrow" `shouldBe` Nothing

        it "accepts past due dates" $ do
            -- User story: "Past dates are valid for overdue tracking"
            parseDueDate "Due: 2020-01-01" `shouldBe` Just (fromGregorian 2020 1 1)

    describe "Full File Parsing" $ do
        it "parses complete todo.txt file" $ do
            let input =
                    T.unlines
                        [ "2025-08-16"
                        , ". Review code @computer"
                        , "x Submit report @done"
                        , "! Fix bug @urgent Due: 2025-08-17"
                        , ""
                        , "2025-08-17"
                        , ". Call client @calls"
                        ]
            case parseTodoFile input of
                Right sections -> do
                    length sections `shouldBe` 2
                    case sections of
                        (firstSection : _) -> length (sectionEntries firstSection) `shouldBe` 3
                        [] -> expectationFailure "Expected at least one section"
                Left err -> expectationFailure $ "Parse failed: " ++ show err
