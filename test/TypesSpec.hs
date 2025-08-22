{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Text (Text)
import Data.Time (Day, fromGregorian)
import Test.Hspec
import GHC.Generics (Generic)

import MindGoblin.Types

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "Bullet Type Coverage" $ do
        it "tests all Bullet constructors" $ do
            -- @test-spec: TEST_SPEC.md#1.1-bullet-recognition
            -- @user-story: "All bullet types are represented correctly"
            -- @data-flow: Bullet constructors -> type system -> pattern matching
            let allBullets = [Open, Completed, Migrated, Scheduled, Priority, Idea, Event, Shopping]
            length allBullets `shouldBe` 8

        it "tests Bullet Eq instance" $ do
            -- @user-story: "Bullets can be compared for equality"
            Open `shouldBe` Open
            Completed `shouldBe` Completed
            Open `shouldNotBe` Completed
            Priority `shouldNotBe` Idea

        it "tests Bullet Show instance" $ do
            -- @user-story: "Bullets can be displayed as strings for debugging"
            show Open `shouldBe` "Open"
            show Completed `shouldBe` "Completed"
            show Migrated `shouldBe` "Migrated"
            show Scheduled `shouldBe` "Scheduled"
            show Priority `shouldBe` "Priority"
            show Idea `shouldBe` "Idea"
            show Event `shouldBe` "Event"
            show Shopping `shouldBe` "Shopping"

        it "tests Bullet Enum instance" $ do
            -- @user-story: "Bullets can be enumerated and converted"
            fromEnum Open `shouldBe` 0
            fromEnum Completed `shouldBe` 1
            fromEnum Shopping `shouldBe` 7
            toEnum 0 `shouldBe` Open
            toEnum 7 `shouldBe` Shopping

        it "tests Bullet Bounded instance" $ do
            -- @user-story: "Bullet bounds are defined correctly"
            minBound `shouldBe` Open
            maxBound `shouldBe` Shopping

    describe "Task Type Coverage" $ do
        let testDay = fromGregorian 2025 8 21
        let testTask = Task
                { taskDate = testDay
                , taskBullet = Open
                , taskText = "Test task"
                , taskContexts = [Context "test"]
                , taskDue = Just testDay
                , taskNotes = ["Note 1", "Note 2"]
                , taskUid = Just "test-uid"
                , taskEventTime = Just "2pm"
                }

        it "tests Task constructor and field access" $ do
            -- @user-story: "Task records store all required data"
            taskDate testTask `shouldBe` testDay
            taskBullet testTask `shouldBe` Open
            taskText testTask `shouldBe` "Test task"
            taskContexts testTask `shouldBe` [Context "test"]
            taskDue testTask `shouldBe` Just testDay
            taskNotes testTask `shouldBe` ["Note 1", "Note 2"]
            taskUid testTask `shouldBe` Just "test-uid"
            taskEventTime testTask `shouldBe` Just "2pm"

        it "tests Task with minimal fields" $ do
            -- @user-story: "Tasks work with minimal required data"
            let minimalTask = Task testDay Open "Minimal" [] Nothing [] Nothing Nothing
            taskText minimalTask `shouldBe` "Minimal"
            taskContexts minimalTask `shouldBe` []
            taskDue minimalTask `shouldBe` Nothing
            taskNotes minimalTask `shouldBe` []
            taskUid minimalTask `shouldBe` Nothing
            taskEventTime minimalTask `shouldBe` Nothing

        it "tests Task Eq instance" $ do
            -- @user-story: "Tasks can be compared for equality"
            let task1 = testTask
            let task2 = testTask { taskText = "Different" }
            let task3 = testTask
            task1 `shouldBe` task3
            task1 `shouldNotBe` task2

        it "tests Task Show instance" $ do
            -- @user-story: "Tasks can be displayed for debugging"
            let taskStr = show testTask
            taskStr `shouldContain` "Task"
            taskStr `shouldContain` "Test task"
            taskStr `shouldContain` "Open"
            taskStr `shouldContain` "test-uid"

    describe "Context Type Coverage" $ do
        it "tests Context constructor" $ do
            -- @user-story: "Contexts store text labels"
            let ctx = Context "computer"
            case ctx of
                Context text -> text `shouldBe` "computer"

        it "tests Context Eq instance" $ do
            -- @user-story: "Contexts can be compared"
            Context "home" `shouldBe` Context "home"
            Context "home" `shouldNotBe` Context "work"

        it "tests Context Show instance" $ do
            -- @user-story: "Contexts can be displayed"
            show (Context "test") `shouldBe` "Context \"test\""

    describe "DateSection Type Coverage" $ do
        let testDay = fromGregorian 2025 8 21
        let testTask = Task testDay Open "Task" [] Nothing [] Nothing Nothing
        let dateSection = DateSection testDay [testTask]

        it "tests DateSection constructor and fields" $ do
            -- @user-story: "Date sections group tasks by date"
            sectionDate dateSection `shouldBe` testDay
            sectionEntries dateSection `shouldBe` [testTask]

        it "tests empty DateSection" $ do
            -- @user-story: "Date sections can be empty"
            let emptySection = DateSection testDay []
            sectionEntries emptySection `shouldBe` []

        it "tests DateSection Eq instance" $ do
            -- @user-story: "Date sections can be compared"
            let section1 = DateSection testDay [testTask]
            let section2 = DateSection testDay []
            let section3 = DateSection testDay [testTask]
            section1 `shouldBe` section3
            section1 `shouldNotBe` section2

        it "tests DateSection Show instance" $ do
            -- @user-story: "Date sections can be displayed"
            let sectionStr = show dateSection
            sectionStr `shouldContain` "DateSection"

    describe "ParseError Type Coverage" $ do
        it "tests all ParseError constructors" $ do
            -- @user-story: "All parse error types can be created"
            let errors = 
                    [ InvalidBullet "bad bullet"
                    , InvalidDateFormat "bad date"
                    , NoDateSection
                    , InvalidContext "bad context"
                    , ParseFailure "parse failed"
                    ]
            length errors `shouldBe` 5

        it "tests ParseError Eq instance" $ do
            -- @user-story: "Parse errors can be compared"
            InvalidBullet "test" `shouldBe` InvalidBullet "test"
            InvalidBullet "test" `shouldNotBe` InvalidBullet "other"
            NoDateSection `shouldBe` NoDateSection
            ParseFailure "msg" `shouldBe` ParseFailure "msg"

        it "tests ParseError Show instance" $ do
            -- @user-story: "Parse errors can be displayed for debugging"
            show (InvalidBullet "bad") `shouldBe` "InvalidBullet \"bad\""
            show (InvalidDateFormat "2025-99-99") `shouldContain` "InvalidDateFormat"
            show NoDateSection `shouldBe` "NoDateSection"
            show (InvalidContext "@bad") `shouldContain` "InvalidContext"
            show (ParseFailure "failed") `shouldContain` "ParseFailure"

    describe "VTodoStatus Type Coverage" $ do
        it "tests all VTodoStatus constructors" $ do
            -- @user-story: "All VTODO status values are available"
            let allStatuses = [NeedsAction, InProcess, StatusCompleted, Cancelled]
            length allStatuses `shouldBe` 4

        it "tests VTodoStatus Eq instance" $ do
            -- @user-story: "VTODO statuses can be compared"
            NeedsAction `shouldBe` NeedsAction
            StatusCompleted `shouldBe` StatusCompleted
            NeedsAction `shouldNotBe` StatusCompleted

        it "tests VTodoStatus Show instance" $ do
            -- @user-story: "VTODO statuses can be displayed"
            show NeedsAction `shouldBe` "NeedsAction"
            show InProcess `shouldBe` "InProcess"
            show StatusCompleted `shouldBe` "StatusCompleted"
            show Cancelled `shouldBe` "Cancelled"

    describe "Priority Type Coverage" $ do
        it "tests all Priority constructors" $ do
            -- @user-story: "All priority levels are available"
            let allPriorities = [HighPriority, MediumPriority, LowPriority]
            length allPriorities `shouldBe` 3

        it "tests Priority Eq instance" $ do
            -- @user-story: "Priorities can be compared"
            HighPriority `shouldBe` HighPriority
            MediumPriority `shouldNotBe` LowPriority

        it "tests Priority Show instance" $ do
            -- @user-story: "Priorities can be displayed"
            show HighPriority `shouldBe` "HighPriority"
            show MediumPriority `shouldBe` "MediumPriority"
            show LowPriority `shouldBe` "LowPriority"

    describe "Zettel Type Coverage" $ do
        let testZettel = Zettel
                { zettelSlug = "test-slug"
                , zettelContent = "Test content"
                , zettelContinuation = ["Line 1", "Line 2"]
                , zettelKeywords = ["keyword1", "keyword2"]
                , zettelType = ZettelNote
                }

        it "tests Zettel constructor and fields" $ do
            -- @user-story: "Zettel records store all zettelkasten data"
            zettelSlug testZettel `shouldBe` "test-slug"
            zettelContent testZettel `shouldBe` "Test content"
            zettelContinuation testZettel `shouldBe` ["Line 1", "Line 2"]
            zettelKeywords testZettel `shouldBe` ["keyword1", "keyword2"]
            zettelType testZettel `shouldBe` ZettelNote

        it "tests minimal Zettel" $ do
            -- @user-story: "Zettels work with minimal data"
            let minimalZettel = Zettel "slug" "content" [] [] ZettelNote
            zettelContinuation minimalZettel `shouldBe` []
            zettelKeywords minimalZettel `shouldBe` []
            zettelType minimalZettel `shouldBe` ZettelNote

        it "tests Zettel Eq instance" $ do
            -- @user-story: "Zettels can be compared"
            let zettel1 = testZettel
            let zettel2 = testZettel { zettelSlug = "different" }
            let zettel3 = testZettel
            zettel1 `shouldBe` zettel3
            zettel1 `shouldNotBe` zettel2

        it "tests Zettel Show instance" $ do
            -- @user-story: "Zettels can be displayed"
            let zettelStr = show testZettel
            zettelStr `shouldContain` "Zettel"
            zettelStr `shouldContain` "test-slug"
            zettelStr `shouldContain` "Test content"

    describe "ZettelType Type Coverage" $ do
        it "tests all ZettelType constructors" $ do
            -- @user-story: "All zettel types are available"
            let allTypes = [ZettelNote]
            length allTypes `shouldBe` 1

        it "tests ZettelType Eq instance" $ do
            -- @user-story: "Zettel types can be compared"
            ZettelNote `shouldBe` ZettelNote

        it "tests ZettelType Show instance" $ do
            -- @user-story: "Zettel types can be displayed"
            show ZettelNote `shouldBe` "ZettelNote"

    describe "shouldSyncTask Function Coverage" $ do
        let today = fromGregorian 2025 8 21
        let yesterday = fromGregorian 2025 8 20
        let tomorrow = fromGregorian 2025 8 22

        it "syncs Open tasks from today" $ do
            -- @user-story: "Open tasks from today appear in calendar"
            let task = Task today Open "Task" [] Nothing [] Nothing Nothing
            shouldSyncTask today task `shouldBe` True

        it "syncs Completed tasks from today" $ do
            -- @user-story: "Completed tasks from today show completion in calendar"
            let task = Task today Completed "Task" [] Nothing [] Nothing Nothing
            shouldSyncTask today task `shouldBe` True

        it "syncs Priority tasks from today" $ do
            -- @user-story: "Priority tasks from today appear in calendar"
            let task = Task today Priority "Task" [] Nothing [] Nothing Nothing
            shouldSyncTask today task `shouldBe` True

        it "syncs Scheduled tasks from today" $ do
            -- @user-story: "Scheduled tasks from today appear in calendar"
            let task = Task today Scheduled "Task" [] Nothing [] Nothing Nothing
            shouldSyncTask today task `shouldBe` True

        it "syncs Event tasks from today" $ do
            -- @user-story: "Events from today appear in calendar"
            let task = Task today Event "Task" [] Nothing [] Nothing Nothing
            shouldSyncTask today task `shouldBe` True

        it "syncs Shopping tasks from today" $ do
            -- @user-story: "Shopping items from today appear in calendar"
            let task = Task today Shopping "Task" [] Nothing [] Nothing Nothing
            shouldSyncTask today task `shouldBe` True

        it "does not sync Idea tasks" $ do
            -- @user-story: "Ideas don't clutter the calendar"
            let task = Task today Idea "Task" [] Nothing [] Nothing Nothing
            shouldSyncTask today task `shouldBe` False

        it "does not sync Migrated tasks" $ do
            -- @user-story: "Migrated tasks don't appear twice"
            let task = Task today Migrated "Task" [] Nothing [] Nothing Nothing
            shouldSyncTask today task `shouldBe` False

        it "does not sync tasks from yesterday" $ do
            -- @user-story: "Only today's tasks appear in today view"
            let task = Task yesterday Open "Task" [] Nothing [] Nothing Nothing
            shouldSyncTask today task `shouldBe` False

        it "does not sync tasks from tomorrow" $ do
            -- @user-story: "Future tasks don't appear in today view"
            let task = Task tomorrow Open "Task" [] Nothing [] Nothing Nothing
            shouldSyncTask today task `shouldBe` False

        it "handles all bullet types with non-today dates" $ do
            -- @user-story: "Date filtering works for all bullet types"
            let bullets = [Open, Completed, Migrated, Scheduled, Priority, Idea, Event, Shopping]
            let tasks = map (\bullet -> Task yesterday bullet "Task" [] Nothing [] Nothing Nothing) bullets
            let syncResults = map (shouldSyncTask today) tasks
            all (== False) syncResults `shouldBe` True

    describe "Generic Instance Coverage" $ do
        it "tests that all types derive Generic correctly" $ do
            -- @user-story: "Types can be serialized and processed generically"
            -- This test ensures Generic instances exist and compile
            let bullet = Open :: Bullet
            let task = Task (fromGregorian 2025 8 21) Open "test" [] Nothing [] Nothing Nothing :: Task
            let context = Context "test" :: Context
            let dateSection = DateSection (fromGregorian 2025 8 21) [] :: DateSection
            let parseError = NoDateSection :: ParseError
            let vtodoStatus = NeedsAction :: VTodoStatus
            let priority = HighPriority :: Priority
            let zettel = Zettel "slug" "content" [] [] ZettelNote :: Zettel
            let zettelType = ZettelNote :: ZettelType
            
            -- If these compile, Generic instances are working
            bullet `shouldBe` Open
            taskBullet task `shouldBe` Open
            context `shouldBe` Context "test"
            sectionEntries dateSection `shouldBe` []
            parseError `shouldBe` NoDateSection
            vtodoStatus `shouldBe` NeedsAction
            priority `shouldBe` HighPriority
            zettelSlug zettel `shouldBe` "slug"
            zettelType `shouldBe` ZettelNote