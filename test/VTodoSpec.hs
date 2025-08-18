{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Test.Hspec
import qualified Data.Text as T
import Data.Time (fromGregorian)

import MindGoblin.Types
import MindGoblin.VTodo

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "ICS File Generation (TEST_SPEC.md#2.1)" $ do
    it "creates valid VTODO structure" $ do
      -- User story: "Files must be valid iCalendar format for compatibility"
      -- Data flow: Task -> VTODO generator -> wrap in VCALENDAR -> valid .ics
      let task = Task 
            { taskDate = fromGregorian 2025 8 16
            , taskBullet = Open
            , taskText = "Buy milk"
            , taskContexts = []
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "550e8400e29b41d4"
            , taskEventTime = Nothing
            }
      let vtodo = taskToVTodo task
      T.unpack vtodo `shouldContain` "BEGIN:VCALENDAR"
      T.unpack vtodo `shouldContain` "BEGIN:VTODO"
      T.unpack vtodo `shouldContain` "END:VTODO"
      T.unpack vtodo `shouldContain` "END:VCALENDAR"

    it "includes RFC5545 compliance headers" $ do
      -- User story: "Files must comply with iCalendar standard"
      let task = Task 
            { taskDate = fromGregorian 2025 8 16
            , taskBullet = Open
            , taskText = "Test task"
            , taskContexts = []
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "550e8400e29b41d4"
            , taskEventTime = Nothing
            }
      let vtodo = taskToVTodo task
      T.unpack vtodo `shouldContain` "VERSION:2.0"
      T.unpack vtodo `shouldContain` "PRODID:"

  describe "VTODO Content (TEST_SPEC.md#2.2)" $ do
    it "maps basic task to VTODO" $ do
      -- User story: "My task text becomes the calendar item summary"
      let task = Task 
            { taskDate = fromGregorian 2025 8 16
            , taskBullet = Open
            , taskText = "Buy milk"
            , taskContexts = []
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "550e8400e29b41d4"
            , taskEventTime = Nothing
            }
      let vtodo = taskToVTodo task
      T.unpack vtodo `shouldContain` "SUMMARY:Buy milk"
      T.unpack vtodo `shouldContain` "STATUS:NEEDS-ACTION"

    it "maps priority task with high priority" $ do
      -- User story: "! tasks show as high priority in calendar apps"
      let task = Task 
            { taskDate = fromGregorian 2025 8 16
            , taskBullet = Priority
            , taskText = "Fix bug"
            , taskContexts = []
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "550e8400e29b41d4"
            , taskEventTime = Nothing
            }
      let vtodo = taskToVTodo task
      T.unpack vtodo `shouldContain` "PRIORITY:1"

    it "maps contexts to CATEGORIES" $ do
      -- User story: "My @contexts become calendar categories for filtering"
      let task = Task 
            { taskDate = fromGregorian 2025 8 16
            , taskBullet = Open
            , taskText = "Work task"
            , taskContexts = [Context "home", Context "urgent"]
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "550e8400e29b41d4"
            , taskEventTime = Nothing
            }
      let vtodo = taskToVTodo task
      T.unpack vtodo `shouldContain` "CATEGORIES:home,urgent"

    it "maps due date to DUE field" $ do
      -- User story: "Due dates sync to calendar apps for deadline tracking"
      let task = Task 
            { taskDate = fromGregorian 2025 8 16
            , taskBullet = Open
            , taskText = "Submit report"
            , taskContexts = []
            , taskDue = Just (fromGregorian 2025 8 20)
            , taskNotes = []
            , taskUid = Just "550e8400e29b41d4"
            , taskEventTime = Nothing
            }
      let vtodo = taskToVTodo task
      T.unpack vtodo `shouldContain` "DUE:20250820"

    it "maps notes to DESCRIPTION" $ do
      -- User story: "My indented notes become the task description"
      let task = Task 
            { taskDate = fromGregorian 2025 8 16
            , taskBullet = Open
            , taskText = "Research topic"
            , taskContexts = []
            , taskDue = Nothing
            , taskNotes = ["Line 1", "Line 2"]
            , taskUid = Just "550e8400e29b41d4"
            , taskEventTime = Nothing
            }
      let vtodo = taskToVTodo task
      T.unpack vtodo `shouldContain` "DESCRIPTION:Line 1\\nLine 2"

    it "escapes special characters in text" $ do
      -- User story: "Commas and special chars are escaped per iCalendar rules"
      let task = Task 
            { taskDate = fromGregorian 2025 8 16
            , taskBullet = Open
            , taskText = "Meeting, review"
            , taskContexts = []
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "550e8400e29b41d4"
            , taskEventTime = Nothing
            }
      let vtodo = taskToVTodo task
      T.unpack vtodo `shouldContain` "SUMMARY:Meeting\\, review"

    it "includes UID field" $ do
      -- User story: "Tasks need unique IDs for sync tracking"
      let task = Task 
            { taskDate = fromGregorian 2025 8 16
            , taskBullet = Open
            , taskText = "Test task"
            , taskContexts = []
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "550e8400e29b41d4"
            , taskEventTime = Nothing
            }
      let vtodo = taskToVTodo task
      T.unpack vtodo `shouldContain` "UID:550e8400e29b41d4"

  describe "Line Folding (TEST_SPEC.md#2.2)" $ do
    it "folds long lines at 75 characters" $ do
      -- User story: "Long lines are folded at 75 chars per iCalendar spec"
      let longText = T.replicate 100 "x"
      let task = Task 
            { taskDate = fromGregorian 2025 8 16
            , taskBullet = Open
            , taskText = longText
            , taskContexts = []
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "550e8400e29b41d4"
            , taskEventTime = Nothing
            }
      let vtodo = taskToVTodo task
      -- Should have line continuation (space at start of next line)
      T.unpack vtodo `shouldContain` "\n "

  describe "VEVENT Generation" $ do
    it "creates VEVENT for event bullets" $ do
      -- User story: "Event bullets (o) appear as calendar events"
      let task = Task 
            { taskDate = fromGregorian 2025 8 17
            , taskBullet = Event
            , taskText = "Team meeting"
            , taskContexts = [Context "work"]
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "event123"
            , taskEventTime = Nothing
            }
      let ics = taskToIcs task
      T.unpack ics `shouldContain` "BEGIN:VEVENT"
      T.unpack ics `shouldContain` "END:VEVENT"
      T.unpack ics `shouldContain` "SUMMARY:Team meeting"
      T.unpack ics `shouldContain` "DTSTART:20250817"
      T.unpack ics `shouldContain` "DTEND:20250817"
      T.unpack ics `shouldContain` "CATEGORIES:work"
      T.unpack ics `shouldNotContain` "BEGIN:VTODO"
    
    it "creates VTODO for non-event bullets" $ do
      -- User story: "Regular tasks remain as todos"
      let task = Task 
            { taskDate = fromGregorian 2025 8 17
            , taskBullet = Open
            , taskText = "Buy milk"
            , taskContexts = []
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "task123"
            , taskEventTime = Nothing
            }
      let ics = taskToIcs task
      T.unpack ics `shouldContain` "BEGIN:VTODO"
      T.unpack ics `shouldContain` "END:VTODO"
      T.unpack ics `shouldNotContain` "BEGIN:VEVENT"

  describe "Date-Based Sync Filtering" $ do
    it "syncs tasks from today" $ do
      -- User story: "I only want to see today's tasks in my calendar app"
      let today = fromGregorian 2025 8 17
      let task = Task 
            { taskDate = today
            , taskBullet = Open
            , taskText = "Today's task"
            , taskContexts = []
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "task123"
            , taskEventTime = Nothing
            }
      shouldSyncTask today task `shouldBe` True

    it "does not sync tasks from yesterday" $ do
      -- User story: "Past tasks shouldn't clutter my calendar"
      let today = fromGregorian 2025 8 17
      let yesterday = fromGregorian 2025 8 16
      let task = Task 
            { taskDate = yesterday
            , taskBullet = Open
            , taskText = "Yesterday's task"
            , taskContexts = []
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "task123"
            , taskEventTime = Nothing
            }
      shouldSyncTask today task `shouldBe` False

    it "does not sync tasks from tomorrow" $ do
      -- User story: "Future tasks shouldn't appear until their day"
      let today = fromGregorian 2025 8 17
      let tomorrow = fromGregorian 2025 8 18
      let task = Task 
            { taskDate = tomorrow
            , taskBullet = Open
            , taskText = "Tomorrow's task"
            , taskContexts = []
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "task123"
            , taskEventTime = Nothing
            }
      shouldSyncTask today task `shouldBe` False

    it "syncs today's priority tasks" $ do
      -- User story: "Today's urgent tasks should sync regardless"
      let today = fromGregorian 2025 8 17
      let task = Task 
            { taskDate = today
            , taskBullet = Priority
            , taskText = "Urgent task"
            , taskContexts = []
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "task123"
            , taskEventTime = Nothing
            }
      shouldSyncTask today task `shouldBe` True

    it "does not sync today's notes" $ do
      -- User story: "Notes never sync, even from today"
      let today = fromGregorian 2025 8 17
      let task = Task 
            { taskDate = today
            , taskBullet = Note
            , taskText = "Today's note"
            , taskContexts = []
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "task123"
            , taskEventTime = Nothing
            }
      shouldSyncTask today task `shouldBe` False

    it "syncs today's completed tasks" $ do
      -- User story: "Completed tasks from today should sync to show progress"
      let today = fromGregorian 2025 8 17
      let task = Task 
            { taskDate = today
            , taskBullet = Completed
            , taskText = "Done task"
            , taskContexts = []
            , taskDue = Nothing
            , taskNotes = []
            , taskUid = Just "task123"
            , taskEventTime = Nothing
            }
      shouldSyncTask today task `shouldBe` True