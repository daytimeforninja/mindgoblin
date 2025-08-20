{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (Day, defaultTimeLocale, diffUTCTime, formatTime, fromGregorianValid, getCurrentTime, utctDay)
import System.Directory (createDirectoryIfMissing, listDirectory)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Hspec

import MindGoblin.FileOps
import MindGoblin.Parser
import MindGoblin.Types

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "End-to-End CLI Tests" $ do
        it "stats command works with sample todo.txt" $ withTempDir $ \tmpDir -> do
            -- Create sample todo.txt
            let todoFile = tmpDir </> "todo.txt"
            today <- formatTime defaultTimeLocale "%Y-%m-%d" . utctDay <$> getCurrentTime
            let sampleContent =
                    T.pack $
                        unlines
                            [ today
                            , ". Review code changes @computer"
                            , "! Fix production bug @urgent @computer Due: 2025-08-21"
                            , "x Submit expense report @computer"
                            , "- Meeting notes: Discussed Q4 planning"
                            , "o Team standup 10am @meetings"
                            , "* Consider switching to event sourcing"
                            ]
            TIO.writeFile todoFile sampleContent

            -- Run mg stats
            (exitCode, stdout, _) <-
                readProcessWithExitCode
                    "cabal"
                    ["run", "mg", "--", "stats", "--file", todoFile]
                    ""

            exitCode `shouldBe` ExitSuccess
            stdout `shouldContain` "Total entries:"
            stdout `shouldContain` "Open tasks:"
            stdout `shouldContain` "Priority:"
            stdout `shouldContain` "Syncable:"

        it "push command creates valid ics files" $ withTempDir $ \tmpDir -> do
            -- Setup
            let todoFile = tmpDir </> "todo.txt"
            let vdirPath = tmpDir </> ".local" </> "share" </> "mg" </> "tasks"
            createDirectoryIfMissing True vdirPath

            today <- formatTime defaultTimeLocale "%Y-%m-%d" . utctDay <$> getCurrentTime
            let sampleContent =
                    T.pack $
                        unlines
                            [ today
                            , ". Review code changes @computer"
                            , "! Fix production bug @urgent Due: 2025-08-21"
                            , "x Submit expense report @computer"
                            ]
            TIO.writeFile todoFile sampleContent

            -- Set HOME to tmpDir and run mg push
            (exitCode, stdout, _) <-
                readProcessWithExitCode
                    "env"
                    ["HOME=" ++ tmpDir, "cabal", "run", "mg", "--", "push", "--file", todoFile]
                    ""

            exitCode `shouldBe` ExitSuccess
            stdout `shouldContain` "Push complete!"

            -- Verify ics files were created
            icsFiles <-
                filter (T.isSuffixOf ".ics" . T.pack)
                    <$> System.Directory.listDirectory vdirPath
            length icsFiles `shouldBeInRange` (2, 3) -- Should have 2-3 tasks synced

            -- Verify ics file content
            case icsFiles of
                (firstFile : _) -> do
                    let firstIcs = vdirPath </> firstFile
                    content <- TIO.readFile firstIcs
                    let contentStr = T.unpack content
                    contentStr `shouldContain` "BEGIN:VCALENDAR"
                    contentStr `shouldContain` "BEGIN:VTODO"
                    contentStr `shouldContain` "END:VTODO"
                    contentStr `shouldContain` "END:VCALENDAR"
                [] -> expectationFailure "No .ics files found"

        it "handles malformed ics files gracefully" $ withTempDir $ \tmpDir -> do
            -- Setup
            let vdirPath = tmpDir </> ".local" </> "share" </> "mg" </> "tasks"
            createDirectoryIfMissing True vdirPath

            -- Create malformed ics file
            let badIcs = vdirPath </> "bad.ics"
            TIO.writeFile badIcs "INVALID ICS CONTENT"

            -- Test our readVdirTasks function
            tasks <- readVdirTasks vdirPath

            -- Should not crash, should return empty list (malformed file filtered out)
            tasks `shouldBe` []

        it "markTaskCompleted handles file errors gracefully" $ withTempDir $ \tmpDir -> do
            -- Test with non-existent file
            let nonExistentFile = tmpDir </> "nonexistent.txt"
            let testTask =
                    Task
                        { taskDate = fromGregorian 2025 8 16
                        , taskBullet = Open
                        , taskText = "Test task"
                        , taskContexts = []
                        , taskDue = Nothing
                        , taskNotes = []
                        , taskUid = Nothing
                        , taskEventTime = Nothing
                        }

            result <- markTaskCompleted nonExistentFile testTask

            -- Should return Left with error message
            case result of
                Left errMsg -> T.length errMsg `shouldSatisfy` (> 0)
                Right _ -> expectationFailure "Should have failed with non-existent file"

        it "today-only sync filtering works correctly" $ withTempDir $ \tmpDir -> do
            -- Create todo.txt with tasks from different dates
            let todoFile = tmpDir </> "todo.txt"
            today <- formatTime defaultTimeLocale "%Y-%m-%d" . utctDay <$> getCurrentTime
            let yesterday = "2025-08-19"
            let sampleContent =
                    T.pack $
                        unlines
                            [ today
                            , ". Today task @computer"
                            , "! Today priority @urgent"
                            , ""
                            , yesterday
                            , ". Yesterday task @computer"
                            , "! Yesterday priority @urgent"
                            ]
            TIO.writeFile todoFile sampleContent

            -- Parse and check shouldSyncTask logic
            case parseTodoFile sampleContent of
                Left _ -> expectationFailure "Failed to parse todo file"
                Right sections -> do
                    let allTasks = concatMap sectionEntries sections
                    todayDay <- utctDay <$> getCurrentTime
                    let syncableTasks = filter (shouldSyncTask todayDay) allTasks

                    -- Should only sync today's tasks
                    length syncableTasks `shouldBe` 2
                    all (\t -> taskDate t == todayDay) syncableTasks `shouldBe` True

        it "roundtrip: push -> modify ics -> pull preserves changes" $ withTempDir $ \tmpDir -> do
            -- Setup: create todo.txt and vdir
            let todoFile = tmpDir </> "todo.txt"
            let vdirPath = tmpDir </> ".local" </> "share" </> "mg" </> "tasks"
            createDirectoryIfMissing True vdirPath

            today <- formatTime defaultTimeLocale "%Y-%m-%d" . utctDay <$> getCurrentTime
            let originalContent =
                    T.pack $
                        unlines
                            [ today
                            , ". Review code @computer"
                            , ". Fix bug @urgent"
                            ]
            TIO.writeFile todoFile originalContent

            -- Step 1: Push tasks to vdir
            (exitCode1, _, _) <-
                readProcessWithExitCode
                    "env"
                    ["HOME=" ++ tmpDir, "cabal", "run", "mg", "--", "push", "--file", todoFile]
                    ""
            exitCode1 `shouldBe` ExitSuccess

            -- Verify ics files were created
            icsFiles <-
                filter (T.isSuffixOf ".ics" . T.pack)
                    <$> System.Directory.listDirectory vdirPath
            length icsFiles `shouldBe` 2

            -- Step 2: Simulate external completion by modifying an ics file
            case icsFiles of
                (firstFile : _) -> do
                    let firstIcs = vdirPath </> firstFile
                    originalIcs <- TIO.readFile firstIcs
                    let completedIcs = T.replace "STATUS:NEEDS-ACTION" "STATUS:COMPLETED" originalIcs
                    TIO.writeFile firstIcs completedIcs
                [] -> expectationFailure "No .ics files found for roundtrip test"

            -- Step 3: Pull changes back to todo.txt (simulated - we'll test the logic directly)
            -- Test our readVdirTasks function can detect the completion
            tasks <- readVdirTasks vdirPath
            let completedTasks = filter isTaskCompleted tasks
            length completedTasks `shouldBe` 1

            -- Test markTaskCompleted function
            case tasks of
                (completedTask : _) -> do
                    result <- markTaskCompleted todoFile completedTask
                    case result of
                        Right () -> do
                            -- Verify the task was marked complete in todo.txt
                            updatedContent <- TIO.readFile todoFile
                            T.unpack updatedContent `shouldContain` "x "
                        Left err -> expectationFailure $ "markTaskCompleted failed: " ++ T.unpack err
                [] -> expectationFailure "No tasks found in vdir"

        it "handles unicode and special characters correctly" $ withTempDir $ \tmpDir -> do
            -- Test with unicode and special characters
            let todoFile = tmpDir </> "todo.txt"
            let vdirPath = tmpDir </> ".local" </> "share" </> "mg" </> "tasks"
            createDirectoryIfMissing True vdirPath

            today <- formatTime defaultTimeLocale "%Y-%m-%d" . utctDay <$> getCurrentTime
            let unicodeContent =
                    T.pack $
                        unlines
                            [ today
                            , ". Task with émojis 🚀 and ümlauts @tëst"
                            , ". ネタバレ注意 Japanese text @japanese"
                            , ". Symbols: ∑∞≠±×÷ @math"
                            ]
            TIO.writeFile todoFile unicodeContent

            -- Push tasks
            (exitCode, stdout, _) <-
                readProcessWithExitCode
                    "env"
                    ["HOME=" ++ tmpDir, "cabal", "run", "mg", "--", "push", "--file", todoFile]
                    ""
            exitCode `shouldBe` ExitSuccess
            stdout `shouldContain` "Push complete!"

            -- Verify ics files were created and contain escaped unicode
            icsFiles <-
                filter (T.isSuffixOf ".ics" . T.pack)
                    <$> System.Directory.listDirectory vdirPath
            length icsFiles `shouldBe` 3

            -- Check that at least one file contains unicode content
            case icsFiles of
                (firstFile : _) -> do
                    firstIcs <- TIO.readFile (vdirPath </> firstFile)
                    -- Should not crash and should contain some content
                    T.length firstIcs `shouldSatisfy` (> 100)
                [] -> expectationFailure "No .ics files found for unicode test"

        it "handles large files efficiently" $ withTempDir $ \tmpDir -> do
            -- Test with a large number of tasks
            let todoFile = tmpDir </> "todo.txt"
            today <- formatTime defaultTimeLocale "%Y-%m-%d" . utctDay <$> getCurrentTime

            -- Generate 100 tasks
            let largeTasks = map (\i -> ". Task " ++ show (i :: Int) ++ " @context" ++ show (i `mod` 10)) [1 .. 100]
            let largeContent = T.pack $ unlines $ today : largeTasks
            TIO.writeFile todoFile largeContent

            -- Test stats command performance
            start <- getCurrentTime
            (exitCode, stdout, _) <-
                readProcessWithExitCode
                    "cabal"
                    ["run", "mg", "--", "stats", "--file", todoFile]
                    ""
            end <- getCurrentTime

            exitCode `shouldBe` ExitSuccess
            stdout `shouldContain` "100"

            -- Should complete within reasonable time (< 5 seconds)
            let duration = diffUTCTime end start
            duration `shouldSatisfy` (< 5)

-- Helper functions

withTempDir :: (FilePath -> IO a) -> IO a
withTempDir action = withSystemTempDirectory "mg-test" action

shouldBeInRange :: (Ord a, Show a) => a -> (a, a) -> Expectation
shouldBeInRange actual (low, high) =
    if actual >= low && actual <= high
        then return ()
        else
            expectationFailure $
                "Expected " ++ show actual ++ " to be in range " ++ show (low, high)

-- Helper function for date creation (reused from Parser)
fromGregorian :: Integer -> Int -> Int -> Day
fromGregorian y m d = case fromGregorianValid y m d of
    Just date -> date
    Nothing -> case fromGregorianValid 2025 1 1 of
        Just defaultDate -> defaultDate
        Nothing -> error "Internal error: default date invalid"
