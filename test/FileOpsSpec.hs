{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (fromGregorian)
import System.Directory (createDirectoryIfMissing, listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

import MindGoblin.FileOps
import MindGoblin.Types

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "File Update Tests (TEST_SPEC.md#4.1)" $ do
        it "changes bullet to completed" $ do
            -- User story: "Completed tasks show as x in my todo.txt"
            -- Data flow: Line with . -> completion detected -> replace . with x -> write line
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                let originalContent = "2025-08-16\n. Buy milk @store"
                TIO.writeFile todoFile originalContent

                let task =
                        Task
                            { taskDate = fromGregorian 2025 8 16
                            , taskBullet = Open
                            , taskText = "Buy milk"
                            , taskContexts = [Context "store"]
                            , taskDue = Nothing
                            , taskNotes = []
                            , taskUid = Just "550e8400e29b41d4"
                            , taskEventTime = Nothing
                            }

                _ <- markTaskCompleted todoFile task

                content <- TIO.readFile todoFile
                T.unpack content `shouldContain` "x Buy milk @store"

        it "preserves task text exactly" $ do
            -- User story: "Only the bullet changes, nothing else"
            -- Data flow: ". Buy milk @store" -> x + " Buy milk @store" -> exact preservation
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                let originalContent = "2025-08-16\n. Buy milk @store Due: 2025-08-20"
                TIO.writeFile todoFile originalContent

                let task =
                        Task
                            { taskDate = fromGregorian 2025 8 16
                            , taskBullet = Open
                            , taskText = "Buy milk"
                            , taskContexts = [Context "store"]
                            , taskDue = Just (fromGregorian 2025 8 20)
                            , taskNotes = []
                            , taskUid = Just "550e8400e29b41d4"
                            , taskEventTime = Nothing
                            }

                _ <- markTaskCompleted todoFile task

                content <- TIO.readFile todoFile
                T.unpack content `shouldContain` "x Buy milk @store Due: 2025-08-20"

        it "keeps files clean without UIDs" $ do
            -- User story: "Files stay clean and readable without UID pollution"
            -- Data flow: Task completion -> bullet change only -> no UIDs added
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                let originalContent = "2025-08-16\n. Buy milk"
                TIO.writeFile todoFile originalContent

                let task =
                        Task
                            { taskDate = fromGregorian 2025 8 16
                            , taskBullet = Open
                            , taskText = "Buy milk"
                            , taskContexts = []
                            , taskDue = Nothing
                            , taskNotes = []
                            , taskUid = Just "550e8400e29b41d4"
                            , taskEventTime = Nothing
                            }

                _ <- markTaskCompleted todoFile task

                content <- TIO.readFile todoFile
                -- Should NOT contain UIDs - file stays clean
                T.unpack content `shouldNotContain` "UID"
                T.unpack content `shouldContain` "x Buy milk"

    describe "File Safety Tests (TEST_SPEC.md#4.2)" $ do
        it "handles file operations safely" $ do
            -- User story: "File operations are safe and don't corrupt data"
            -- Data flow: Atomic write operations ensure file integrity
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                let originalContent = "2025-08-16\n. Test task"
                TIO.writeFile todoFile originalContent

                let task =
                        Task
                            { taskDate = fromGregorian 2025 8 16
                            , taskBullet = Open
                            , taskText = "Test task"
                            , taskContexts = []
                            , taskDue = Nothing
                            , taskNotes = []
                            , taskUid = Just "550e8400e29b41d4"
                            , taskEventTime = Nothing
                            }

                _ <- markTaskCompleted todoFile task

                -- Check file was updated correctly
                content <- TIO.readFile todoFile
                T.unpack content `shouldContain` "x Test task"

        it "uses atomic write operations" $ do
            -- User story: "File updates never leave partial data"
            -- Data flow: Write todo.txt.tmp -> fsync -> rename to todo.txt -> atomic
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                let originalContent = "2025-08-16\n. Test task"
                TIO.writeFile todoFile originalContent

                let task =
                        Task
                            { taskDate = fromGregorian 2025 8 16
                            , taskBullet = Open
                            , taskText = "Test task"
                            , taskContexts = []
                            , taskDue = Nothing
                            , taskNotes = []
                            , taskUid = Just "550e8400e29b41d4"
                            , taskEventTime = Nothing
                            }

                -- This test mainly ensures the operation completes without error
                -- The atomic nature is tested by ensuring no .tmp files remain
                _ <- markTaskCompleted todoFile task

                files <- listDirectory tmpDir
                let tmpFiles = filter (T.isSuffixOf ".tmp" . T.pack) files
                tmpFiles `shouldBe` []

    describe "vdir Writing Tests (TEST_SPEC.md#3.3)" $ do
        it "creates new .ics for open tasks" $ do
            -- User story: "New tasks in todo.txt appear in my calendar"
            -- Data flow: New task -> generate deterministic UID -> create .ics in vdir
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let vdirPath = tmpDir </> "vdir" </> "tasks"
                createDirectoryIfMissing True vdirPath

                let task =
                        Task
                            { taskDate = fromGregorian 2025 8 16
                            , taskBullet = Open
                            , taskText = "New task"
                            , taskContexts = [Context "work"]
                            , taskDue = Nothing
                            , taskNotes = []
                            , taskUid = Just "550e8400e29b41d4"
                            , taskEventTime = Nothing
                            }

                writeTaskToVdir vdirPath task

                -- The filename is based on deterministic UID from content hash
                files <- listDirectory vdirPath
                length files `shouldBe` 1

                case files of
                    (fileName : _) -> do
                        let actualFile = vdirPath </> fileName
                        content <- TIO.readFile actualFile
                        T.unpack content `shouldContain` "SUMMARY:New task"
                        T.unpack content `shouldContain` "CATEGORIES:work"
                    [] -> expectationFailure "Expected at least one file in vdir"

    describe "vdir Reading Tests (TEST_SPEC.md#3.1)" $ do
        it "parses all .ics files in vdir" $ do
            -- User story: "All calendar files in vdir are checked for updates"
            -- Data flow: List vdir/*.ics -> parse each -> extract VTODO data
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let vdirPath = tmpDir </> "vdir" </> "tasks"
                createDirectoryIfMissing True vdirPath

                -- Create test .ics files
                let task1 =
                        Task
                            { taskDate = fromGregorian 2025 8 16
                            , taskBullet = Open
                            , taskText = "Task 1"
                            , taskContexts = []
                            , taskDue = Nothing
                            , taskNotes = []
                            , taskUid = Just "550e8400e29b41d1"
                            , taskEventTime = Nothing
                            }

                let task2 =
                        Task
                            { taskDate = fromGregorian 2025 8 16
                            , taskBullet = Completed
                            , taskText = "Task 2"
                            , taskContexts = []
                            , taskDue = Nothing
                            , taskNotes = []
                            , taskUid = Just "550e8400e29b41d2"
                            , taskEventTime = Nothing
                            }

                writeTaskToVdir vdirPath task1
                writeTaskToVdir vdirPath task2

                tasks <- readVdirTasks vdirPath
                length tasks `shouldBe` 2

        it "extracts completion status from .ics files" $ do
            -- User story: "Completed tasks in calendar apps are detected"
            -- Data flow: .ics file -> parse VTODO -> STATUS:COMPLETED found -> marked done
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let vdirPath = tmpDir </> "vdir" </> "tasks"
                createDirectoryIfMissing True vdirPath

                let completedTask =
                        Task
                            { taskDate = fromGregorian 2025 8 16
                            , taskBullet = Completed
                            , taskText = "Completed task"
                            , taskContexts = []
                            , taskDue = Nothing
                            , taskNotes = []
                            , taskUid = Just "550e8400e29b41d4"
                            , taskEventTime = Nothing
                            }

                writeTaskToVdir vdirPath completedTask

                tasks <- readVdirTasks vdirPath
                case tasks of
                    (task : _) -> isTaskCompleted task `shouldBe` True
                    [] -> expectationFailure "No tasks found"

    describe "Coverage for Missing Code Paths" $ do
        it "handles non-existent todo file gracefully" $ do
            -- @user-story: "Missing files produce clear error messages"
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let todoFile = tmpDir </> "nonexistent.txt"
                let task = Task (fromGregorian 2025 8 16) Open "Task" [] Nothing [] Nothing Nothing
                result <- markTaskCompleted todoFile task
                case result of
                    Left err -> T.unpack err `shouldContain` "Todo file does not exist"
                    Right _ -> expectationFailure "Should have failed with missing file"

        it "handles priority bullet completion" $ do
            -- @user-story: "Priority tasks can be completed"
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                let originalContent = "2025-08-16\n! Urgent task @work"
                TIO.writeFile todoFile originalContent

                let task = Task (fromGregorian 2025 8 16) Priority "Urgent task" [Context "work"] Nothing [] Nothing Nothing
                _ <- markTaskCompleted todoFile task

                content <- TIO.readFile todoFile
                T.unpack content `shouldContain` "x Urgent task @work"

        it "handles event bullet completion" $ do
            -- @user-story: "Event tasks can be completed"
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                let originalContent = "2025-08-16\no Meeting @work"
                TIO.writeFile todoFile originalContent

                let task = Task (fromGregorian 2025 8 16) Event "Meeting" [Context "work"] Nothing [] Nothing Nothing
                _ <- markTaskCompleted todoFile task

                content <- TIO.readFile todoFile
                T.unpack content `shouldContain` "x Meeting @work"

        it "handles scheduled bullet completion" $ do
            -- @user-story: "Scheduled tasks can be completed"
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                let originalContent = "2025-08-16\n< Scheduled task"
                TIO.writeFile todoFile originalContent

                let task = Task (fromGregorian 2025 8 16) Scheduled "Scheduled task" [] Nothing [] Nothing Nothing
                _ <- markTaskCompleted todoFile task

                content <- TIO.readFile todoFile
                T.unpack content `shouldContain` "x Scheduled task"

        it "leaves non-matching bullets unchanged" $ do
            -- @user-story: "Non-actionable bullets are preserved"
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                let originalContent = "2025-08-16\n- Note item\n* Idea item"
                TIO.writeFile todoFile originalContent

                let task = Task (fromGregorian 2025 8 16) Idea "Idea item" [] Nothing [] Nothing Nothing
                _ <- markTaskCompleted todoFile task

                content <- TIO.readFile todoFile
                T.unpack content `shouldContain` "- Note item"
                T.unpack content `shouldContain` "* Idea item" -- No change expected

        it "handles empty vdir directory" $ do
            -- @user-story: "Empty directories don't cause errors"
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let vdirPath = tmpDir </> "empty-vdir"
                createDirectoryIfMissing True vdirPath
                tasks <- readVdirTasks vdirPath
                tasks `shouldBe` []

        it "handles invalid iCalendar format gracefully" $ do
            -- @user-story: "Malformed calendar files don't crash the system"
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let vdirPath = tmpDir </> "vdir"
                createDirectoryIfMissing True vdirPath
                
                -- Create invalid .ics file
                let invalidIcs = "INVALID CALENDAR FORMAT\nNO BEGIN/END TAGS"
                TIO.writeFile (vdirPath </> "invalid.ics") invalidIcs

                tasks <- readVdirTasks vdirPath
                tasks `shouldBe` [] -- Should return empty list, not crash

        it "cleans up old .ics files correctly" $ do
            -- @user-story: "Old task files are cleaned from vdir"
            withSystemTempDirectory "mg-test" $ \tmpDir -> do
                let vdirPath = tmpDir </> "vdir"
                createDirectoryIfMissing True vdirPath

                -- Create old files that should be removed
                TIO.writeFile (vdirPath </> "old1.ics") "old content"
                TIO.writeFile (vdirPath </> "old2.ics") "old content"
                TIO.writeFile (vdirPath </> "readme.txt") "not ics - should be kept"

                -- Create a task and corresponding file that should be kept
                let task = Task (fromGregorian 2025 8 16) Open "Keep this" [] Nothing [] Nothing Nothing
                writeTaskToVdir vdirPath task

                cleanVdirForTasks vdirPath [task]

                files <- listDirectory vdirPath
                length files `shouldSatisfy` (> 0)
                files `shouldSatisfy` elem "readme.txt" -- Non-ics files preserved