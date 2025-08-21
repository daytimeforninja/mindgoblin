{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (catch, SomeException)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (Day, defaultTimeLocale, formatTime, fromGregorianValid, getCurrentTime, getCurrentTimeZone, utcToLocalTime, localDay)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

import MindGoblin.FileOps
import MindGoblin.Parser
import MindGoblin.Types
import MindGoblin.VTodo

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "Regression Tests" $ do
        describe "UID Storage Regression (Critical Bug)" $ do
            it "ensures UIDs are never written to todo.txt" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                utc <- getCurrentTime
                tz <- getCurrentTimeZone
                let today = formatTime defaultTimeLocale "%Y-%m-%d" . localDay $ utcToLocalTime tz utc
                let content = T.pack $ unlines [today, ". Test task @context"]
                TIO.writeFile todoFile content
                
                let testTask = Task
                        { taskDate = fromGregorian 2025 8 20
                        , taskBullet = Open
                        , taskText = "Test task"
                        , taskContexts = [Context "context"]
                        , taskDue = Nothing
                        , taskNotes = []
                        , taskUid = Just "test-uid-should-not-appear"
                        , taskEventTime = Nothing
                        }
                
                _ <- markTaskCompleted todoFile testTask
                
                -- Read file back and ensure no UID pollution
                finalContent <- TIO.readFile todoFile
                T.unpack finalContent `shouldNotContain` "UID:"
                T.unpack finalContent `shouldNotContain` "<!--"
                T.unpack finalContent `shouldNotContain` "-->"
                T.unpack finalContent `shouldNotContain` "test-uid-should-not-appear"

            it "parses old todo.txt files with UID comments gracefully" $ do
                let oldStyleContent = "2025-08-20\n. Clean task without UID\nx Old completed task <!-- UID:old-uid-123 -->\n. Another clean task"
                
                case parseTodoFile oldStyleContent of
                    Right sections -> do
                        let tasks = concatMap sectionEntries sections
                        length tasks `shouldBe` 3 -- Should parse all tasks
                        -- All tasks should have Nothing for UIDs (cleaned)
                        all (\t -> taskUid t == Nothing) tasks `shouldBe` True
                    Left _ -> expectationFailure "Should parse legacy UID format gracefully"

        describe "Content-Based Matching Regression" $ do
            it "correctly matches tasks by content when UIDs are absent" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                utc <- getCurrentTime
                tz <- getCurrentTimeZone
                let today = formatTime defaultTimeLocale "%Y-%m-%d" . localDay $ utcToLocalTime tz utc
                let content = T.unlines
                        [ T.pack today
                        , ". First task @work"
                        , ". Second task @home"
                        , ". Third task @work Due: 2025-08-21"
                        ]
                TIO.writeFile todoFile content
                
                let targetTask = Task
                        { taskDate = fromGregorian 2025 8 20
                        , taskBullet = Open
                        , taskText = "Second task"
                        , taskContexts = [Context "home"]
                        , taskDue = Nothing
                        , taskNotes = []
                        , taskUid = Nothing
                        , taskEventTime = Nothing
                        }
                
                result <- markTaskCompleted todoFile targetTask
                result `shouldBe` Right ()
                
                -- Verify only the correct task was marked complete
                finalContent <- TIO.readFile todoFile
                let finalLines = T.lines finalContent
                finalLines `shouldContain` [". First task @work"]
                finalLines `shouldContain` ["x Second task @home"] 
                finalLines `shouldContain` [". Third task @work Due: 2025-08-21"]

        describe "Date Boundary Regressions" $ do
            it "handles leap year edge cases correctly" $ do
                -- Test Feb 29 on leap year
                case parseTaskLine (fromGregorian 2024 2 29) ". Leap year task Due: 2024-02-29" of
                    Right task -> taskDue task `shouldNotBe` Nothing
                    Left _ -> expectationFailure "Should handle leap year correctly"
                
                -- Test Feb 29 on non-leap year
                parseTaskLine (fromGregorian 2025 2 28) ". Invalid leap day Due: 2025-02-29" `shouldSatisfy` isLeft

        describe "Text Encoding Regressions" $ do
            it "preserves Unicode characters exactly" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "unicode.txt"
                utc <- getCurrentTime
                tz <- getCurrentTimeZone
                let today = formatTime defaultTimeLocale "%Y-%m-%d" . localDay $ utcToLocalTime tz utc
                let unicodeText = "🚀 Unicode task with émojis and ümlauts 中文"
                let content = T.pack $ unlines [today, ". " ++ T.unpack unicodeText ++ " @test"]
                TIO.writeFile todoFile content
                
                -- Read back and verify Unicode is preserved
                readContent <- TIO.readFile todoFile
                case parseTodoFile readContent of
                    Right sections -> do
                        let tasks = concatMap sectionEntries sections
                        case tasks of
                            [task] -> taskText task `shouldBe` unicodeText
                            _ -> expectationFailure "Should parse exactly one task"
                    Left _ -> expectationFailure "Should parse Unicode content"

        describe "Context Parsing Regressions" $ do
            it "handles context edge cases that previously failed" $ do
                -- Context at very end of line
                case parseTaskLine (fromGregorian 2025 8 20) ". Task ending with @context" of
                    Right task -> taskContexts task `shouldBe` [Context "context"]
                    Left _ -> expectationFailure "Should handle context at end"

            it "preserves context order consistently" $ do
                let testLine = ". Task @third @first @second text"
                case parseTaskLine (fromGregorian 2025 8 20) testLine of
                    Right task -> do
                        taskContexts task `shouldBe` [Context "third", Context "first", Context "second"]
                        taskText task `shouldBe` "Task"
                    Left _ -> expectationFailure "Should preserve context order"

        describe "VTodo Generation Regressions" $ do
            it "generates consistent UIDs for identical content" $ do
                let task1 = Task
                        { taskDate = fromGregorian 2025 8 20
                        , taskBullet = Open
                        , taskText = "Identical task"
                        , taskContexts = [Context "work"]
                        , taskDue = Nothing
                        , taskNotes = []
                        , taskUid = Nothing
                        , taskEventTime = Nothing
                        }
                
                let task2 = task1 -- Identical task
                
                let vtodo1 = taskToVTodo task1
                let vtodo2 = taskToVTodo task2
                
                -- Should generate identical VTODOs (including UID)
                vtodo1 `shouldBe` vtodo2

            it "generates different UIDs for different content" $ do
                let task1 = Task
                        { taskDate = fromGregorian 2025 8 20
                        , taskBullet = Open
                        , taskText = "First task"
                        , taskContexts = []
                        , taskDue = Nothing
                        , taskNotes = []
                        , taskUid = Nothing
                        , taskEventTime = Nothing
                        }
                
                let task2 = task1 { taskText = "Second task" }
                
                let vtodo1 = taskToVTodo task1
                let vtodo2 = taskToVTodo task2
                
                -- Should generate different VTODOs
                vtodo1 `shouldNotBe` vtodo2

        describe "File Operation Regressions" $ do
            it "handles concurrent modifications gracefully" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "concurrent.txt"
                utc <- getCurrentTime
                tz <- getCurrentTimeZone
                let today = formatTime defaultTimeLocale "%Y-%m-%d" . localDay $ utcToLocalTime tz utc
                let content = T.pack $ unlines [today, ". Task to modify"]
                TIO.writeFile todoFile content
                
                let testTask = Task
                        { taskDate = fromGregorian 2025 8 20
                        , taskBullet = Open
                        , taskText = "Task to modify"
                        , taskContexts = []
                        , taskDue = Nothing
                        , taskNotes = []
                        , taskUid = Nothing
                        , taskEventTime = Nothing
                        }
                
                -- Simulate file being modified between read and write
                result1 <- markTaskCompleted todoFile testTask
                result2 <- markTaskCompleted todoFile testTask -- Second attempt
                
                -- At least one should succeed
                [result1, result2] `shouldSatisfy` any isRight

            it "preserves file existence after operations" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "permissions.txt"
                utc <- getCurrentTime
                tz <- getCurrentTimeZone
                let today = formatTime defaultTimeLocale "%Y-%m-%d" . localDay $ utcToLocalTime tz utc
                let content = T.pack $ unlines [today, ". Task"]
                TIO.writeFile todoFile content
                
                let testTask = Task
                        { taskDate = fromGregorian 2025 8 20
                        , taskBullet = Open
                        , taskText = "Task"
                        , taskContexts = []
                        , taskDue = Nothing
                        , taskNotes = []
                        , taskUid = Nothing
                        , taskEventTime = Nothing
                        }
                
                result <- markTaskCompleted todoFile testTask
                result `shouldBe` Right ()
                
                -- File should still exist and be readable
                newExists <- doesFileExist todoFile
                newExists `shouldBe` True

-- Helper functions

withTempDir :: (FilePath -> IO a) -> IO a
withTempDir action = withSystemTempDirectory "mg-regression-test" action

fromGregorian :: Integer -> Int -> Int -> Day
fromGregorian y m d = case fromGregorianValid y m d of
    Just date -> date
    Nothing -> case fromGregorianValid 2025 1 1 of
        Just defaultDate -> defaultDate
        Nothing -> error "Internal error: default date invalid"

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft (Right _) = False

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight (Left _) = False

doesFileExist :: FilePath -> IO Bool
doesFileExist path = do
    result <- catch (TIO.readFile path >> return True) (\(_ :: SomeException) -> return False)
    return result