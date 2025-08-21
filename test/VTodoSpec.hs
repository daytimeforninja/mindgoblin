{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Text qualified as T
import Data.Time (fromGregorian)
import Test.Hspec

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
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldContain` "BEGIN:VCALENDAR"
            T.unpack vtodo `shouldContain` "BEGIN:VTODO"
            T.unpack vtodo `shouldContain` "END:VTODO"
            T.unpack vtodo `shouldContain` "END:VCALENDAR"

        it "includes RFC5545 compliance headers" $ do
            -- User story: "Files must comply with iCalendar standard"
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
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldContain` "VERSION:2.0"
            T.unpack vtodo `shouldContain` "PRODID:"

    describe "VTODO Content (TEST_SPEC.md#2.2)" $ do
        it "maps basic task to VTODO" $ do
            -- User story: "My task text becomes the calendar item summary"
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
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldContain` "SUMMARY:Buy milk"
            T.unpack vtodo `shouldContain` "STATUS:NEEDS-ACTION"

        it "maps priority task with high priority" $ do
            -- User story: "! tasks show as high priority in calendar apps"
            let task =
                    Task
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
            let task =
                    Task
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
            let task =
                    Task
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
            let task =
                    Task
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
            let task =
                    Task
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

        it "includes deterministic UID field" $ do
            -- User story: "Tasks need unique IDs for sync tracking"
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
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldContain` "UID:550e8400e29b41d4"

    describe "Line Folding (TEST_SPEC.md#2.2)" $ do
        it "folds long lines at 75 characters" $ do
            -- User story: "Long lines are folded at 75 chars per iCalendar spec"
            let longText = T.replicate 100 "x"
            let task =
                    Task
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
            let task =
                    Task
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
            let task =
                    Task
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
            let task =
                    Task
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

    describe "Comprehensive VTodo Coverage" $ do
        it "handles completed status correctly" $ do
            -- @user-story: "Completed tasks show as COMPLETED in calendar"
            let task = Task (fromGregorian 2025 8 17) Completed "Done task" [] Nothing [] (Just "uid123") Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldContain` "STATUS:COMPLETED"

        it "handles all bullet types via taskToVTodo" $ do
            -- @user-story: "All bullet types map to appropriate VTODO status"
            let testTaskWithBullet bullet = Task (fromGregorian 2025 8 17) bullet "Test" [] Nothing [] (Just "uid") Nothing
            T.unpack (taskToVTodo (testTaskWithBullet Open)) `shouldContain` "STATUS:NEEDS-ACTION"
            T.unpack (taskToVTodo (testTaskWithBullet Priority)) `shouldContain` "STATUS:NEEDS-ACTION"
            T.unpack (taskToVTodo (testTaskWithBullet Completed)) `shouldContain` "STATUS:COMPLETED"
            T.unpack (taskToVTodo (testTaskWithBullet Migrated)) `shouldContain` "STATUS:NEEDS-ACTION"
            T.unpack (taskToVTodo (testTaskWithBullet Scheduled)) `shouldContain` "STATUS:NEEDS-ACTION"
            T.unpack (taskToVTodo (testTaskWithBullet Idea)) `shouldContain` "STATUS:NEEDS-ACTION"
            T.unpack (taskToVTodo (testTaskWithBullet Shopping)) `shouldContain` "STATUS:NEEDS-ACTION"

        it "handles missing UID gracefully" $ do
            -- @user-story: "Tasks without UIDs get default UID"
            let task = Task (fromGregorian 2025 8 17) Open "No UID task" [] Nothing [] Nothing Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldContain` "UID:unknown"

        it "handles empty contexts list" $ do
            -- @user-story: "Tasks without contexts don't have CATEGORIES line"
            let task = Task (fromGregorian 2025 8 17) Open "No contexts" [] Nothing [] (Just "uid123") Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldNotContain` "CATEGORIES:"

        it "handles empty notes list" $ do
            -- @user-story: "Tasks without notes don't have DESCRIPTION line"
            let task = Task (fromGregorian 2025 8 17) Open "No notes" [] Nothing [] (Just "uid123") Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldNotContain` "DESCRIPTION:"

        it "handles no due date" $ do
            -- @user-story: "Tasks without due dates don't have DUE line"
            let task = Task (fromGregorian 2025 8 17) Open "No due" [] Nothing [] (Just "uid123") Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldNotContain` "DUE:"

        it "handles non-priority bullets for priority line" $ do
            -- @user-story: "Only Priority bullet gets PRIORITY field"
            let task = Task (fromGregorian 2025 8 17) Open "Regular task" [] Nothing [] (Just "uid123") Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldNotContain` "PRIORITY:"

    describe "Text Escaping Coverage" $ do
        it "escapes all special characters" $ do
            -- @user-story: "All RFC5545 special characters are properly escaped"
            escapeText "comma," `shouldBe` "comma\\,"
            escapeText "semicolon;" `shouldBe` "semicolon\\;"
            escapeText "newline\n" `shouldBe` "newline\\n"
            escapeText "backslash\\" `shouldBe` "backslash\\\\"

        it "escapes multiple characters together" $ do
            -- @user-story: "Multiple special characters are all escaped"
            escapeText "test,;\\n\n" `shouldBe` "test\\,\\;\\\\n\\n"

        it "handles empty text" $ do
            -- @user-story: "Empty text is handled gracefully"
            escapeText "" `shouldBe` ""

        it "handles text without special characters" $ do
            -- @user-story: "Regular text passes through unchanged"
            escapeText "regular text" `shouldBe` "regular text"

    describe "Line Folding Coverage" $ do
        it "doesn't fold short lines" $ do
            -- @user-story: "Short lines remain unchanged"
            let shortText = T.replicate 50 "x"
            foldLine shortText `shouldBe` shortText

        it "folds exactly 75 character lines" $ do
            -- @user-story: "Lines at 75 chars don't need folding"
            let exactText = T.replicate 75 "x"
            foldLine exactText `shouldBe` exactText

        it "folds lines over 75 characters" $ do
            -- @user-story: "Lines over 75 chars are folded with continuation"
            let longText = T.replicate 100 "x"
            let folded = foldLine longText
            T.unpack folded `shouldContain` "\n "
            T.length (T.takeWhile (/= '\n') folded) `shouldBe` 75

        it "handles very long lines with multiple folds" $ do
            -- @user-story: "Very long lines are folded multiple times"
            let veryLongText = T.replicate 200 "a"
            let folded = foldLine veryLongText
            let foldCount = T.count "\n " folded
            foldCount `shouldSatisfy` (>= 2)

    describe "VEVENT Generation Coverage" $ do
        it "handles event with missing UID" $ do
            -- @user-story: "Events without UIDs get default UID"
            let task = Task (fromGregorian 2025 8 17) Event "Meeting" [] Nothing [] Nothing Nothing
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "UID:unknown"

        it "handles event with empty contexts" $ do
            -- @user-story: "Events without contexts don't have CATEGORIES line"
            let task = Task (fromGregorian 2025 8 17) Event "Meeting" [] Nothing [] (Just "uid123") Nothing
            let ics = taskToIcs task
            T.unpack ics `shouldNotContain` "CATEGORIES:"

        it "handles event with empty notes" $ do
            -- @user-story: "Events without notes don't have DESCRIPTION line"
            let task = Task (fromGregorian 2025 8 17) Event "Meeting" [] Nothing [] (Just "uid123") Nothing
            let ics = taskToIcs task
            T.unpack ics `shouldNotContain` "DESCRIPTION:"

        it "handles event with specific time" $ do
            -- @user-story: "Events with times get proper DTSTART/DTEND"
            let task = Task (fromGregorian 2025 8 17) Event "Meeting" [] Nothing [] (Just "uid123") (Just "2pm")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T140000"
            T.unpack ics `shouldContain` "DTEND:20250817T150000"

        it "handles event with time range" $ do
            -- @user-story: "Events with time ranges use start and end times"
            let task = Task (fromGregorian 2025 8 17) Event "Long meeting" [] Nothing [] (Just "uid123") (Just "2-4pm")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T140000"
            T.unpack ics `shouldContain` "DTEND:20250817T160000"

        it "handles event with AM time" $ do
            -- @user-story: "AM times are parsed correctly"
            let task = Task (fromGregorian 2025 8 17) Event "Morning meeting" [] Nothing [] (Just "uid123") (Just "9am")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T090000"
            T.unpack ics `shouldContain` "DTEND:20250817T100000"

        it "handles event with 24-hour time" $ do
            -- @user-story: "24-hour format times are parsed correctly"
            let task = Task (fromGregorian 2025 8 17) Event "Formal meeting" [] Nothing [] (Just "uid123") (Just "14:30")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T143000"
            T.unpack ics `shouldContain` "DTEND:20250817T150000"

        it "handles event with 12pm (noon)" $ do
            -- @user-story: "12pm is correctly parsed as noon"
            let task = Task (fromGregorian 2025 8 17) Event "Lunch" [] Nothing [] (Just "uid123") (Just "12pm")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T120000"

        it "handles event with 12am (midnight)" $ do
            -- @user-story: "12am is correctly parsed as midnight"
            let task = Task (fromGregorian 2025 8 17) Event "Late task" [] Nothing [] (Just "uid123") (Just "12am")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T000000"

        it "handles event with invalid time format" $ do
            -- @user-story: "Invalid times default to 2pm"
            let task = Task (fromGregorian 2025 8 17) Event "Bad time" [] Nothing [] (Just "uid123") (Just "invalid")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T140000"

        it "handles event with malformed time range" $ do
            -- @user-story: "Malformed ranges default to single time"
            let task = Task (fromGregorian 2025 8 17) Event "Bad range" [] Nothing [] (Just "uid123") (Just "2-3-4pm")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T140000"

        it "handles event with mixed case AM/PM" $ do
            -- @user-story: "Mixed case times work correctly"
            let task = Task (fromGregorian 2025 8 17) Event "Mixed case" [] Nothing [] (Just "uid123") (Just "3PM")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T150000"

        it "handles edge case of 23:xx time for end time calculation" $ do
            -- @user-story: "Late times don't overflow past midnight"
            let task = Task (fromGregorian 2025 8 17) Event "Late meeting" [] Nothing [] (Just "uid123") (Just "23:30")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T233000"
            T.unpack ics `shouldContain` "DTEND:20250817T000000" -- Wraps to next day

        it "does not sync tasks from yesterday" $ do
            -- User story: "Past tasks shouldn't clutter my calendar"
            let today = fromGregorian 2025 8 17
            let yesterday = fromGregorian 2025 8 16
            let task =
                    Task
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
            let task =
                    Task
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
            let task =
                    Task
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

    describe "Comprehensive VTodo Coverage" $ do
        it "handles completed status correctly" $ do
            -- @user-story: "Completed tasks show as COMPLETED in calendar"
            let task = Task (fromGregorian 2025 8 17) Completed "Done task" [] Nothing [] (Just "uid123") Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldContain` "STATUS:COMPLETED"

        it "handles all bullet types via taskToVTodo" $ do
            -- @user-story: "All bullet types map to appropriate VTODO status"
            let testTaskWithBullet bullet = Task (fromGregorian 2025 8 17) bullet "Test" [] Nothing [] (Just "uid") Nothing
            T.unpack (taskToVTodo (testTaskWithBullet Open)) `shouldContain` "STATUS:NEEDS-ACTION"
            T.unpack (taskToVTodo (testTaskWithBullet Priority)) `shouldContain` "STATUS:NEEDS-ACTION"
            T.unpack (taskToVTodo (testTaskWithBullet Completed)) `shouldContain` "STATUS:COMPLETED"
            T.unpack (taskToVTodo (testTaskWithBullet Migrated)) `shouldContain` "STATUS:NEEDS-ACTION"
            T.unpack (taskToVTodo (testTaskWithBullet Scheduled)) `shouldContain` "STATUS:NEEDS-ACTION"
            T.unpack (taskToVTodo (testTaskWithBullet Idea)) `shouldContain` "STATUS:NEEDS-ACTION"
            T.unpack (taskToVTodo (testTaskWithBullet Shopping)) `shouldContain` "STATUS:NEEDS-ACTION"

        it "handles missing UID gracefully" $ do
            -- @user-story: "Tasks without UIDs get default UID"
            let task = Task (fromGregorian 2025 8 17) Open "No UID task" [] Nothing [] Nothing Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldContain` "UID:unknown"

        it "handles empty contexts list" $ do
            -- @user-story: "Tasks without contexts don't have CATEGORIES line"
            let task = Task (fromGregorian 2025 8 17) Open "No contexts" [] Nothing [] (Just "uid123") Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldNotContain` "CATEGORIES:"

        it "handles empty notes list" $ do
            -- @user-story: "Tasks without notes don't have DESCRIPTION line"
            let task = Task (fromGregorian 2025 8 17) Open "No notes" [] Nothing [] (Just "uid123") Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldNotContain` "DESCRIPTION:"

        it "handles no due date" $ do
            -- @user-story: "Tasks without due dates don't have DUE line"
            let task = Task (fromGregorian 2025 8 17) Open "No due" [] Nothing [] (Just "uid123") Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldNotContain` "DUE:"

        it "handles non-priority bullets for priority line" $ do
            -- @user-story: "Only Priority bullet gets PRIORITY field"
            let task = Task (fromGregorian 2025 8 17) Open "Regular task" [] Nothing [] (Just "uid123") Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldNotContain` "PRIORITY:"

    describe "Text Escaping Coverage" $ do
        it "escapes all special characters" $ do
            -- @user-story: "All RFC5545 special characters are properly escaped"
            escapeText "comma," `shouldBe` "comma\\,"
            escapeText "semicolon;" `shouldBe` "semicolon\\;"
            escapeText "newline\n" `shouldBe` "newline\\n"
            escapeText "backslash\\" `shouldBe` "backslash\\\\"

        it "escapes multiple characters together" $ do
            -- @user-story: "Multiple special characters are all escaped"
            escapeText "test,;\\n\n" `shouldBe` "test\\,\\;\\\\n\\n"

        it "handles empty text" $ do
            -- @user-story: "Empty text is handled gracefully"
            escapeText "" `shouldBe` ""

        it "handles text without special characters" $ do
            -- @user-story: "Regular text passes through unchanged"
            escapeText "regular text" `shouldBe` "regular text"

    describe "Line Folding Coverage" $ do
        it "doesn't fold short lines" $ do
            -- @user-story: "Short lines remain unchanged"
            let shortText = T.replicate 50 "x"
            foldLine shortText `shouldBe` shortText

        it "folds exactly 75 character lines" $ do
            -- @user-story: "Lines at 75 chars don't need folding"
            let exactText = T.replicate 75 "x"
            foldLine exactText `shouldBe` exactText

        it "folds lines over 75 characters" $ do
            -- @user-story: "Lines over 75 chars are folded with continuation"
            let longText = T.replicate 100 "x"
            let folded = foldLine longText
            T.unpack folded `shouldContain` "\n "
            T.length (T.takeWhile (/= '\n') folded) `shouldBe` 75

        it "handles very long lines with multiple folds" $ do
            -- @user-story: "Very long lines are folded multiple times"
            let veryLongText = T.replicate 200 "a"
            let folded = foldLine veryLongText
            let foldCount = T.count "\n " folded
            foldCount `shouldSatisfy` (>= 2)

    describe "VEVENT Generation Coverage" $ do
        it "handles event with missing UID" $ do
            -- @user-story: "Events without UIDs get default UID"
            let task = Task (fromGregorian 2025 8 17) Event "Meeting" [] Nothing [] Nothing Nothing
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "UID:unknown"

        it "handles event with empty contexts" $ do
            -- @user-story: "Events without contexts don't have CATEGORIES line"
            let task = Task (fromGregorian 2025 8 17) Event "Meeting" [] Nothing [] (Just "uid123") Nothing
            let ics = taskToIcs task
            T.unpack ics `shouldNotContain` "CATEGORIES:"

        it "handles event with empty notes" $ do
            -- @user-story: "Events without notes don't have DESCRIPTION line"
            let task = Task (fromGregorian 2025 8 17) Event "Meeting" [] Nothing [] (Just "uid123") Nothing
            let ics = taskToIcs task
            T.unpack ics `shouldNotContain` "DESCRIPTION:"

        it "handles event with specific time" $ do
            -- @user-story: "Events with times get proper DTSTART/DTEND"
            let task = Task (fromGregorian 2025 8 17) Event "Meeting" [] Nothing [] (Just "uid123") (Just "2pm")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T140000"
            T.unpack ics `shouldContain` "DTEND:20250817T150000"

        it "handles event with time range" $ do
            -- @user-story: "Events with time ranges use start and end times"
            let task = Task (fromGregorian 2025 8 17) Event "Long meeting" [] Nothing [] (Just "uid123") (Just "2-4pm")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T140000"
            T.unpack ics `shouldContain` "DTEND:20250817T160000"

        it "handles event with AM time" $ do
            -- @user-story: "AM times are parsed correctly"
            let task = Task (fromGregorian 2025 8 17) Event "Morning meeting" [] Nothing [] (Just "uid123") (Just "9am")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T090000"
            T.unpack ics `shouldContain` "DTEND:20250817T100000"

        it "handles event with 24-hour time" $ do
            -- @user-story: "24-hour format times are parsed correctly"
            let task = Task (fromGregorian 2025 8 17) Event "Formal meeting" [] Nothing [] (Just "uid123") (Just "14:30")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T143000"
            T.unpack ics `shouldContain` "DTEND:20250817T150000"

        it "handles event with 12pm (noon)" $ do
            -- @user-story: "12pm is correctly parsed as noon"
            let task = Task (fromGregorian 2025 8 17) Event "Lunch" [] Nothing [] (Just "uid123") (Just "12pm")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T120000"

        it "handles event with 12am (midnight)" $ do
            -- @user-story: "12am is correctly parsed as midnight"
            let task = Task (fromGregorian 2025 8 17) Event "Late task" [] Nothing [] (Just "uid123") (Just "12am")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T000000"

        it "handles event with invalid time format" $ do
            -- @user-story: "Invalid times default to 2pm"
            let task = Task (fromGregorian 2025 8 17) Event "Bad time" [] Nothing [] (Just "uid123") (Just "invalid")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T140000"

        it "handles event with malformed time range" $ do
            -- @user-story: "Malformed ranges default to single time"
            let task = Task (fromGregorian 2025 8 17) Event "Bad range" [] Nothing [] (Just "uid123") (Just "2-3-4pm")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T140000"

        it "handles event with mixed case AM/PM" $ do
            -- @user-story: "Mixed case times work correctly"
            let task = Task (fromGregorian 2025 8 17) Event "Mixed case" [] Nothing [] (Just "uid123") (Just "3PM")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T150000"

        it "handles edge case of 23:xx time for end time calculation" $ do
            -- @user-story: "Late times don't overflow past midnight"
            let task = Task (fromGregorian 2025 8 17) Event "Late meeting" [] Nothing [] (Just "uid123") (Just "23:30")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T233000"
            T.unpack ics `shouldContain` "DTEND:20250817T000000" -- Wraps to next day


        it "syncs today's completed tasks" $ do
            -- User story: "Completed tasks from today should sync to show progress"
            let today = fromGregorian 2025 8 17
            let task =
                    Task
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

    describe "Comprehensive VTodo Coverage" $ do
        it "handles completed status correctly" $ do
            -- @user-story: "Completed tasks show as COMPLETED in calendar"
            let task = Task (fromGregorian 2025 8 17) Completed "Done task" [] Nothing [] (Just "uid123") Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldContain` "STATUS:COMPLETED"

        it "handles all bullet types via taskToVTodo" $ do
            -- @user-story: "All bullet types map to appropriate VTODO status"
            let testTaskWithBullet bullet = Task (fromGregorian 2025 8 17) bullet "Test" [] Nothing [] (Just "uid") Nothing
            T.unpack (taskToVTodo (testTaskWithBullet Open)) `shouldContain` "STATUS:NEEDS-ACTION"
            T.unpack (taskToVTodo (testTaskWithBullet Priority)) `shouldContain` "STATUS:NEEDS-ACTION"
            T.unpack (taskToVTodo (testTaskWithBullet Completed)) `shouldContain` "STATUS:COMPLETED"
            T.unpack (taskToVTodo (testTaskWithBullet Migrated)) `shouldContain` "STATUS:NEEDS-ACTION"
            T.unpack (taskToVTodo (testTaskWithBullet Scheduled)) `shouldContain` "STATUS:NEEDS-ACTION"
            T.unpack (taskToVTodo (testTaskWithBullet Idea)) `shouldContain` "STATUS:NEEDS-ACTION"
            T.unpack (taskToVTodo (testTaskWithBullet Shopping)) `shouldContain` "STATUS:NEEDS-ACTION"

        it "handles missing UID gracefully" $ do
            -- @user-story: "Tasks without UIDs get default UID"
            let task = Task (fromGregorian 2025 8 17) Open "No UID task" [] Nothing [] Nothing Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldContain` "UID:unknown"

        it "handles empty contexts list" $ do
            -- @user-story: "Tasks without contexts don't have CATEGORIES line"
            let task = Task (fromGregorian 2025 8 17) Open "No contexts" [] Nothing [] (Just "uid123") Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldNotContain` "CATEGORIES:"

        it "handles empty notes list" $ do
            -- @user-story: "Tasks without notes don't have DESCRIPTION line"
            let task = Task (fromGregorian 2025 8 17) Open "No notes" [] Nothing [] (Just "uid123") Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldNotContain` "DESCRIPTION:"

        it "handles no due date" $ do
            -- @user-story: "Tasks without due dates don't have DUE line"
            let task = Task (fromGregorian 2025 8 17) Open "No due" [] Nothing [] (Just "uid123") Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldNotContain` "DUE:"

        it "handles non-priority bullets for priority line" $ do
            -- @user-story: "Only Priority bullet gets PRIORITY field"
            let task = Task (fromGregorian 2025 8 17) Open "Regular task" [] Nothing [] (Just "uid123") Nothing
            let vtodo = taskToVTodo task
            T.unpack vtodo `shouldNotContain` "PRIORITY:"

    describe "Text Escaping Coverage" $ do
        it "escapes all special characters" $ do
            -- @user-story: "All RFC5545 special characters are properly escaped"
            escapeText "comma," `shouldBe` "comma\\,"
            escapeText "semicolon;" `shouldBe` "semicolon\\;"
            escapeText "newline\n" `shouldBe` "newline\\n"
            escapeText "backslash\\" `shouldBe` "backslash\\\\"

        it "escapes multiple characters together" $ do
            -- @user-story: "Multiple special characters are all escaped"
            escapeText "test,;\\n\n" `shouldBe` "test\\,\\;\\\\n\\n"

        it "handles empty text" $ do
            -- @user-story: "Empty text is handled gracefully"
            escapeText "" `shouldBe` ""

        it "handles text without special characters" $ do
            -- @user-story: "Regular text passes through unchanged"
            escapeText "regular text" `shouldBe` "regular text"

    describe "Line Folding Coverage" $ do
        it "doesn't fold short lines" $ do
            -- @user-story: "Short lines remain unchanged"
            let shortText = T.replicate 50 "x"
            foldLine shortText `shouldBe` shortText

        it "folds exactly 75 character lines" $ do
            -- @user-story: "Lines at 75 chars don't need folding"
            let exactText = T.replicate 75 "x"
            foldLine exactText `shouldBe` exactText

        it "folds lines over 75 characters" $ do
            -- @user-story: "Lines over 75 chars are folded with continuation"
            let longText = T.replicate 100 "x"
            let folded = foldLine longText
            T.unpack folded `shouldContain` "\n "
            T.length (T.takeWhile (/= '\n') folded) `shouldBe` 75

        it "handles very long lines with multiple folds" $ do
            -- @user-story: "Very long lines are folded multiple times"
            let veryLongText = T.replicate 200 "a"
            let folded = foldLine veryLongText
            let foldCount = T.count "\n " folded
            foldCount `shouldSatisfy` (>= 2)

    describe "VEVENT Generation Coverage" $ do
        it "handles event with missing UID" $ do
            -- @user-story: "Events without UIDs get default UID"
            let task = Task (fromGregorian 2025 8 17) Event "Meeting" [] Nothing [] Nothing Nothing
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "UID:unknown"

        it "handles event with empty contexts" $ do
            -- @user-story: "Events without contexts don't have CATEGORIES line"
            let task = Task (fromGregorian 2025 8 17) Event "Meeting" [] Nothing [] (Just "uid123") Nothing
            let ics = taskToIcs task
            T.unpack ics `shouldNotContain` "CATEGORIES:"

        it "handles event with empty notes" $ do
            -- @user-story: "Events without notes don't have DESCRIPTION line"
            let task = Task (fromGregorian 2025 8 17) Event "Meeting" [] Nothing [] (Just "uid123") Nothing
            let ics = taskToIcs task
            T.unpack ics `shouldNotContain` "DESCRIPTION:"

        it "handles event with specific time" $ do
            -- @user-story: "Events with times get proper DTSTART/DTEND"
            let task = Task (fromGregorian 2025 8 17) Event "Meeting" [] Nothing [] (Just "uid123") (Just "2pm")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T140000"
            T.unpack ics `shouldContain` "DTEND:20250817T150000"

        it "handles event with time range" $ do
            -- @user-story: "Events with time ranges use start and end times"
            let task = Task (fromGregorian 2025 8 17) Event "Long meeting" [] Nothing [] (Just "uid123") (Just "2-4pm")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T140000"
            T.unpack ics `shouldContain` "DTEND:20250817T160000"

        it "handles event with AM time" $ do
            -- @user-story: "AM times are parsed correctly"
            let task = Task (fromGregorian 2025 8 17) Event "Morning meeting" [] Nothing [] (Just "uid123") (Just "9am")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T090000"
            T.unpack ics `shouldContain` "DTEND:20250817T100000"

        it "handles event with 24-hour time" $ do
            -- @user-story: "24-hour format times are parsed correctly"
            let task = Task (fromGregorian 2025 8 17) Event "Formal meeting" [] Nothing [] (Just "uid123") (Just "14:30")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T143000"
            T.unpack ics `shouldContain` "DTEND:20250817T150000"

        it "handles event with 12pm (noon)" $ do
            -- @user-story: "12pm is correctly parsed as noon"
            let task = Task (fromGregorian 2025 8 17) Event "Lunch" [] Nothing [] (Just "uid123") (Just "12pm")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T120000"

        it "handles event with 12am (midnight)" $ do
            -- @user-story: "12am is correctly parsed as midnight"
            let task = Task (fromGregorian 2025 8 17) Event "Late task" [] Nothing [] (Just "uid123") (Just "12am")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T000000"

        it "handles event with invalid time format" $ do
            -- @user-story: "Invalid times default to 2pm"
            let task = Task (fromGregorian 2025 8 17) Event "Bad time" [] Nothing [] (Just "uid123") (Just "invalid")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T140000"

        it "handles event with malformed time range" $ do
            -- @user-story: "Malformed ranges default to single time"
            let task = Task (fromGregorian 2025 8 17) Event "Bad range" [] Nothing [] (Just "uid123") (Just "2-3-4pm")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T140000"

        it "handles event with mixed case AM/PM" $ do
            -- @user-story: "Mixed case times work correctly"
            let task = Task (fromGregorian 2025 8 17) Event "Mixed case" [] Nothing [] (Just "uid123") (Just "3PM")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T150000"

        it "handles edge case of 23:xx time for end time calculation" $ do
            -- @user-story: "Late times don't overflow past midnight"
            let task = Task (fromGregorian 2025 8 17) Event "Late meeting" [] Nothing [] (Just "uid123") (Just "23:30")
            let ics = taskToIcs task
            T.unpack ics `shouldContain` "DTSTART:20250817T233000"
            T.unpack ics `shouldContain` "DTEND:20250817T000000" -- Wraps to next day
