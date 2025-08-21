{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Text qualified as T
import Data.Time (Day, fromGregorianValid)
import Test.Hspec

import MindGoblin.Parser
import MindGoblin.Types
import MindGoblin.VTodo

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "Edge Case Tests" $ do
        describe "Parser Edge Cases" $ do
            it "handles empty input" $
                parseTodoFile "" `shouldBe` Right []

            it "handles whitespace-only input" $
                parseTodoFile "   \n\t  \n   " `shouldBe` Right []

            it "handles bullet without space" $
                parseTaskLine (fromGregorian 2025 8 20) ".task" `shouldSatisfy` isLeft

            it "handles multiple spaces after bullet" $
                case parseTaskLine (fromGregorian 2025 8 20) ".    task with spaces" of
                    Right task -> taskText task `shouldBe` "task with spaces"
                    Left _ -> expectationFailure "Should handle multiple spaces"

            it "handles trailing whitespace" $
                case parseTaskLine (fromGregorian 2025 8 20) ". task with trailing   " of
                    Right task -> taskText task `shouldBe` "task with trailing"
                    Left _ -> expectationFailure "Should trim trailing whitespace"

            it "handles empty context" $
                parseTaskLine (fromGregorian 2025 8 20) ". task @ more text" `shouldSatisfy` isLeft

            it "handles context with special characters" $
                case parseTaskLine (fromGregorian 2025 8 20) ". task @context-with_special:chars" of
                    Right task -> taskContexts task `shouldContain` [Context "context-with_special:chars"]
                    Left _ -> expectationFailure "Should handle special chars in context"

            it "handles invalid dates gracefully" $ do
                parseTaskLine (fromGregorian 2025 8 20) ". task Due: 2025-02-30" `shouldSatisfy` isLeft
                parseTaskLine (fromGregorian 2025 8 20) ". task Due: 2025-13-01" `shouldSatisfy` isLeft
                parseTaskLine (fromGregorian 2025 8 20) ". task Due: 2025-00-01" `shouldSatisfy` isLeft

            it "handles leap year correctly" $
                case parseTaskLine (fromGregorian 2025 8 20) ". task Due: 2024-02-29" of
                    Right task -> taskDue task `shouldNotBe` Nothing
                    Left _ -> expectationFailure "Should handle leap year"

            it "handles midnight times" $
                case parseTaskLine (fromGregorian 2025 8 20) ". task Due: 2025-08-20 00:00" of
                    Right task -> taskDue task `shouldNotBe` Nothing
                    Left _ -> expectationFailure "Should handle midnight"

        describe "Date Parsing Edge Cases" $ do
            it "handles single digit dates" $
                parseDateSection "2025-1-1\n. task" `shouldSatisfy` isRight

            it "handles leading zeros" $
                parseDateSection "2025-01-01\n. task" `shouldSatisfy` isRight

            it "rejects impossible dates" $ do
                parseDateSection "2025-13-01\n. task" `shouldSatisfy` isLeft
                parseDateSection "2025-00-01\n. task" `shouldSatisfy` isLeft
                parseDateSection "2025-01-32\n. task" `shouldSatisfy` isLeft
                parseDateSection "2025-01-00\n. task" `shouldSatisfy` isLeft

        describe "Context Extraction Edge Cases" $ do
            it "handles @ at end of line" $
                extractContexts "task text @" `shouldBe` []

            it "handles multiple @ symbols" $
                extractContexts "@@double @valid" `shouldBe` [Context "valid"]

            it "handles @ in URLs and emails" $
                extractContexts "email user@domain.com and @valid" `shouldBe` [Context "valid"]

            it "handles context with numbers only" $
                extractContexts "task @123 text" `shouldBe` [Context "123"]

            it "rejects Unicode in contexts" $
                extractContexts "task @café text" `shouldBe` []  -- Should reject non-ASCII

        describe "VTodo Edge Cases" $ do
            it "handles empty task text" $ do
                let emptyTask = Task
                        { taskDate = fromGregorian 2025 8 20
                        , taskBullet = Open
                        , taskText = ""
                        , taskContexts = []
                        , taskDue = Nothing
                        , taskNotes = []
                        , taskUid = Nothing
                        , taskEventTime = Nothing
                        }
                let vtodo = taskToVTodo emptyTask
                T.unpack vtodo `shouldContain` "SUMMARY:"

            it "handles special characters that need escaping" $ do
                let specialTask = Task
                        { taskDate = fromGregorian 2025 8 20
                        , taskBullet = Open
                        , taskText = "Task with , ; \\ and \n newlines"
                        , taskContexts = []
                        , taskDue = Nothing
                        , taskNotes = []
                        , taskUid = Nothing
                        , taskEventTime = Nothing
                        }
                let vtodo = taskToVTodo specialTask
                -- Should escape special chars
                T.unpack vtodo `shouldContain` "\\,"
                T.unpack vtodo `shouldContain` "\\;"
                T.unpack vtodo `shouldContain` "\\n"

        describe "Bullet Type Edge Cases" $ do
            it "handles all bullet types" $ do
                let bullets = [minBound..maxBound] :: [Bullet]
                mapM_ (\bullet -> do
                    let bulletChar = case bullet of
                            Open -> "."
                            Completed -> "x"
                            Migrated -> ">"
                            Scheduled -> "<"
                            Priority -> "!"
                            Idea -> "*"
                            Event -> "o"
                            Shopping -> "$"
                    parseBullet bulletChar `shouldBe` Right bullet
                    ) bullets

            it "rejects invalid bullet characters" $ do
                let invalidBullets = ["a", "1", " ", "", "++", "z"]
                mapM_ (\bullet -> parseBullet (T.pack bullet) `shouldSatisfy` isLeft) invalidBullets

        describe "File Format Edge Cases" $ do
            it "handles mixed line endings" $
                parseTodoFile "2025-08-20\r\n. Task 1\n. Task 2\r. Task 3" `shouldSatisfy` isRight

            it "handles files without final newline" $
                parseTodoFile "2025-08-20\n. Task without final newline" `shouldSatisfy` isRight

            it "handles multiple consecutive newlines" $
                parseTodoFile "2025-08-20\n\n\n. Task after empty lines\n\n\n" `shouldSatisfy` isRight

            it "rejects tabs after bullets" $
                parseTaskLine (fromGregorian 2025 8 20) ".\ttask with tab" `shouldSatisfy` isLeft

        describe "Unicode Edge Cases" $ do
            it "handles decomposed Unicode gracefully" $
                parseTodoFile "2025-08-20\n. café task" `shouldSatisfy` isRight

            it "handles right-to-left text gracefully" $
                parseTodoFile "2025-08-20\n. Arabic text: مرحبا" `shouldSatisfy` isRight

            it "handles emoji text gracefully" $
                parseTodoFile "2025-08-20\n. Task with 🚀 emoji" `shouldSatisfy` isRight

        describe "Boundary Value Tests" $ do
            it "handles extremely long task text" $ do
                let longText = T.replicate 10000 "a"
                let content = "2025-08-20\n. " <> longText
                parseTodoFile content `shouldSatisfy` isRight

            it "handles many contexts" $ do
                let manyContexts = T.intercalate " " (map (\i -> "@context" <> T.pack (show (i :: Int))) [1..100])
                let content = "2025-08-20\n. Task " <> manyContexts
                case parseTodoFile content of
                    Right sections -> 
                        let tasks = concatMap sectionEntries sections
                        in case tasks of
                            [task] -> length (taskContexts task) `shouldBe` 100
                            _ -> expectationFailure "Should parse exactly one task"
                    Left _ -> expectationFailure "Should parse many contexts"

            it "handles maximum valid date" $
                parseDateSection "2100-12-31\n. task" `shouldSatisfy` isRight

            it "handles minimum valid date" $
                parseDateSection "1900-01-01\n. task" `shouldSatisfy` isRight

-- Helper functions

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft (Right _) = False

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight (Left _) = False

fromGregorian :: Integer -> Int -> Int -> Day
fromGregorian y m d = case fromGregorianValid y m d of
    Just date -> date
    Nothing -> case fromGregorianValid 2025 1 1 of
        Just defaultDate -> defaultDate
        Nothing -> error "Internal error: default date invalid"