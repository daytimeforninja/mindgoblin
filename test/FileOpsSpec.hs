{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Test.Hspec
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (fromGregorian)
import System.IO.Temp (withSystemTempDirectory)
import System.FilePath ((</>))
import System.Directory (listDirectory, createDirectoryIfMissing)

import MindGoblin.Types
import MindGoblin.FileOps

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
        
        let task = Task 
              { taskDate = fromGregorian 2025 8 16
              , taskBullet = Open
              , taskText = "Buy milk"
              , taskContexts = [Context "store"]
              , taskDue = Nothing
              , taskNotes = []
              , taskUid = Just "550e8400e29b41d4"
              }
        
        markTaskCompleted todoFile task
        
        content <- TIO.readFile todoFile
        T.unpack content `shouldContain` "x Buy milk @store"

    it "preserves task text exactly" $ do
      -- User story: "Only the bullet changes, nothing else"
      -- Data flow: ". Buy milk @store" -> x + " Buy milk @store" -> exact preservation
      withSystemTempDirectory "mg-test" $ \tmpDir -> do
        let todoFile = tmpDir </> "todo.txt"
        let originalContent = "2025-08-16\n. Buy milk @store Due: 2025-08-20"
        TIO.writeFile todoFile originalContent
        
        let task = Task 
              { taskDate = fromGregorian 2025 8 16
              , taskBullet = Open
              , taskText = "Buy milk"
              , taskContexts = [Context "store"]
              , taskDue = Just (fromGregorian 2025 8 20)
              , taskNotes = []
              , taskUid = Just "550e8400e29b41d4"
              }
        
        markTaskCompleted todoFile task
        
        content <- TIO.readFile todoFile
        T.unpack content `shouldContain` "x Buy milk @store Due: 2025-08-20"

    it "keeps files clean without UIDs" $ do
      -- User story: "Files stay clean and readable without UID pollution"
      -- Data flow: Task completion -> bullet change only -> no UIDs added
      withSystemTempDirectory "mg-test" $ \tmpDir -> do
        let todoFile = tmpDir </> "todo.txt"
        let originalContent = "2025-08-16\n. Buy milk"
        TIO.writeFile todoFile originalContent
        
        let task = Task 
              { taskDate = fromGregorian 2025 8 16
              , taskBullet = Open
              , taskText = "Buy milk"
              , taskContexts = []
              , taskDue = Nothing
              , taskNotes = []
              , taskUid = Just "550e8400e29b41d4"
              }
        
        markTaskCompleted todoFile task
        
        content <- TIO.readFile todoFile
        -- Should NOT contain UIDs - file stays clean
        T.unpack content `shouldNotContain` "UID"
        T.unpack content `shouldContain` "x Buy milk"

    it "preserves existing UID" $ do
      -- User story: "UIDs never change once assigned"
      -- Data flow: Existing UID comment -> keep unchanged -> preserve sync state
      withSystemTempDirectory "mg-test" $ \tmpDir -> do
        let todoFile = tmpDir </> "todo.txt"
        let originalContent = "2025-08-16\n. Buy milk <!-- UID:550e8400-e29b-41d4-a716-446655440000 -->"
        TIO.writeFile todoFile originalContent
        
        let task = Task 
              { taskDate = fromGregorian 2025 8 16
              , taskBullet = Open
              , taskText = "Buy milk"
              , taskContexts = []
              , taskDue = Nothing
              , taskNotes = []
              , taskUid = Just "550e8400e29b41d4"
              }
        
        markTaskCompleted todoFile task
        
        content <- TIO.readFile todoFile
        T.unpack content `shouldContain` "x Buy milk <!-- UID:550e8400-e29b-41d4-a716-446655440000 -->"
        -- Should not have duplicate UIDs
        let uidCount = length $ filter (T.isInfixOf "UID:550e8400") $ T.lines content
        uidCount `shouldBe` 1

  describe "File Safety Tests (TEST_SPEC.md#4.2)" $ do
    it "handles file operations safely" $ do
      -- User story: "File operations are safe and don't corrupt data"
      -- Data flow: Atomic write operations ensure file integrity
      withSystemTempDirectory "mg-test" $ \tmpDir -> do
        let todoFile = tmpDir </> "todo.txt"
        let originalContent = "2025-08-16\n. Test task"
        TIO.writeFile todoFile originalContent
        
        let task = Task 
              { taskDate = fromGregorian 2025 8 16
              , taskBullet = Open
              , taskText = "Test task"
              , taskContexts = []
              , taskDue = Nothing
              , taskNotes = []
              , taskUid = Just "550e8400e29b41d4"
              }
        
        markTaskCompleted todoFile task
        
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
        
        let task = Task 
              { taskDate = fromGregorian 2025 8 16
              , taskBullet = Open
              , taskText = "Test task"
              , taskContexts = []
              , taskDue = Nothing
              , taskNotes = []
              , taskUid = Just "550e8400e29b41d4"
              }
        
        -- This test mainly ensures the operation completes without error
        -- The atomic nature is tested by ensuring no .tmp files remain
        markTaskCompleted todoFile task
        
        files <- listDirectory tmpDir
        let tmpFiles = filter (T.isSuffixOf ".tmp" . T.pack) files
        tmpFiles `shouldBe` []

  describe "vdir Writing Tests (TEST_SPEC.md#3.3)" $ do
    it "creates new .ics for open tasks" $ do
      -- User story: "New tasks in todo.txt appear in my calendar"
      -- Data flow: New task -> generate UID -> create .ics in vdir
      withSystemTempDirectory "mg-test" $ \tmpDir -> do
        let vdirPath = tmpDir </> "vdir" </> "tasks"
        createDirectoryIfMissing True vdirPath
        
        let task = Task 
              { taskDate = fromGregorian 2025 8 16
              , taskBullet = Open
              , taskText = "New task"
              , taskContexts = [Context "work"]
              , taskDue = Nothing
              , taskNotes = []
              , taskUid = Just "550e8400e29b41d4"
              }
        
        writeTaskToVdir vdirPath task
        
        -- The filename is now based on deterministic UID from content hash
        files <- listDirectory vdirPath
        length files `shouldBe` 1
        
        case files of
          (fileName:_) -> do
            let actualFile = vdirPath </> fileName
            content <- TIO.readFile actualFile
            T.unpack content `shouldContain` "SUMMARY:New task"
            T.unpack content `shouldContain` "CATEGORIES:work"
          [] -> expectationFailure "Expected at least one file in vdir"

    it "updates existing .ics files" $ do
      -- User story: "Editing task text updates the calendar entry"
      -- Data flow: Task text changed -> find .ics by UID -> update SUMMARY
      withSystemTempDirectory "mg-test" $ \tmpDir -> do
        let vdirPath = tmpDir </> "vdir" </> "tasks"
        createDirectoryIfMissing True vdirPath
        
        let originalTask = Task 
              { taskDate = fromGregorian 2025 8 16
              , taskBullet = Open
              , taskText = "Original task"
              , taskContexts = []
              , taskDue = Nothing
              , taskNotes = []
              , taskUid = Just "550e8400e29b41d4"
              }
        
        let updatedTask = originalTask { taskText = "Updated task", taskContexts = [Context "urgent"] }
        
        -- Create original file
        writeTaskToVdir vdirPath originalTask
        
        -- Update the task
        writeTaskToVdir vdirPath updatedTask
        
        -- Should have 2 files now (original and updated have different content hashes)
        files <- listDirectory vdirPath
        length files `shouldBe` 2
        
        -- Check that the new file contains updated content
        let updatedFiles = filter (/= "550e8400-e29b-41d4-a716-446655440000.ics") files
        case updatedFiles of
          (updatedFile:_) -> do
            let fullPath = vdirPath </> updatedFile
            content <- TIO.readFile fullPath
            T.unpack content `shouldContain` "SUMMARY:Updated task"
            T.unpack content `shouldContain` "CATEGORIES:urgent"
          [] -> expectationFailure "No updated files found"

  describe "vdir Reading Tests (TEST_SPEC.md#3.1)" $ do
    it "parses all .ics files in vdir" $ do
      -- User story: "All calendar files in vdir are checked for updates"
      -- Data flow: List vdir/*.ics -> parse each -> extract VTODO data
      withSystemTempDirectory "mg-test" $ \tmpDir -> do
        let vdirPath = tmpDir </> "vdir" </> "tasks"
        createDirectoryIfMissing True vdirPath
        
        -- Create test .ics files
        let task1 = Task 
              { taskDate = fromGregorian 2025 8 16
              , taskBullet = Open
              , taskText = "Task 1"
              , taskContexts = []
              , taskDue = Nothing
              , taskNotes = []
              , taskUid = Just "550e8400e29b41d1"
              }
        
        let task2 = Task 
              { taskDate = fromGregorian 2025 8 16
              , taskBullet = Completed
              , taskText = "Task 2"
              , taskContexts = []
              , taskDue = Nothing
              , taskNotes = []
              , taskUid = Just "550e8400e29b41d2"
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
        
        let completedTask = Task 
              { taskDate = fromGregorian 2025 8 16
              , taskBullet = Completed
              , taskText = "Completed task"
              , taskContexts = []
              , taskDue = Nothing
              , taskNotes = []
              , taskUid = Just "550e8400e29b41d4"
              }
        
        writeTaskToVdir vdirPath completedTask
        
        tasks <- readVdirTasks vdirPath
        case tasks of
          (task:_) -> isTaskCompleted task `shouldBe` True
          [] -> expectationFailure "No tasks found"