{-# LANGUAGE DeriveGeneric #-}

module MindGoblin.Types (
    Bullet (..),
    Task (..),
    Context (..),
    DateSection (..),
    ParseError (..),
    VTodoStatus (..),
    Priority (..),
    Zettel (..),
    ZettelType (..),
    shouldSyncTask,
) where

import Data.Text (Text)
import Data.Time (Day)
import GHC.Generics (Generic)

{- | Bullet journal notation symbols
@test-spec: TEST_SPEC.md#1.1-bullet-recognition
@implements: README.md#bullet-types
-}
data Bullet
    = -- | . (needs action)
      Open
    | -- | x (done)
      Completed
    | -- | > (moved)
      Migrated
    | -- | < (timed)
      Scheduled
    | -- | ! (urgent)
      Priority
    | -- | * (future)
      Idea
    | -- | o (appointment)
      Event
    | -- | $ (shopping item)
      Shopping
    deriving (Eq, Show, Enum, Bounded, Generic)

{- | A single task entry
@test-spec: TEST_SPEC.md#1.2-task-parsing
@implements: README.md#file-format-specification
-}
data Task = Task
    { taskDate :: Day
    , taskBullet :: Bullet
    , taskText :: Text
    , taskContexts :: [Context]
    , taskDue :: Maybe Day
    , taskNotes :: [Text]
    , taskUid :: Maybe Text -- Internal only - never stored in todo.txt
    , taskEventTime :: Maybe Text -- Time for events (e.g., "2pm", "14:00")
    }
    deriving (Eq, Show, Generic)

{- | GTD context (e.g., @computer, @home)
@test-spec: TEST_SPEC.md#1.4-context-extraction
@implements: README.md#file-format-specification
-}
newtype Context = Context Text
    deriving (Eq, Show, Generic)

{- | A date section containing tasks
@test-spec: TEST_SPEC.md#1.3-date-section
@implements: README.md#file-format-specification
-}
data DateSection = DateSection
    { sectionDate :: Day
    , sectionEntries :: [Task]
    }
    deriving (Eq, Show, Generic)

-- | Parse errors
data ParseError
    = InvalidBullet Text
    | InvalidDateFormat Text
    | NoDateSection
    | InvalidContext Text
    | ParseFailure String
    deriving (Eq, Show, Generic)

{- | VTODO status values
@test-spec: TEST_SPEC.md#3.2-completion-detection
@implements: README.md#task-to-vtodo-mapping
-}
data VTodoStatus
    = NeedsAction
    | InProcess
    | StatusCompleted
    | Cancelled
    deriving (Eq, Show, Generic)

-- | Task priority levels
data Priority
    = HighPriority -- 1-3 in iCalendar
    | MediumPriority -- 4-6 in iCalendar
    | LowPriority -- 7-9 in iCalendar
    deriving (Eq, Show, Generic)

{- | Zettelkasten entry for knowledge management
@test-spec: ZETTLE.md#parsing
@implements: ZETTLE.md#data-types
@user-story: Users capture fleeting thoughts as zettel seeds
@data-flow: Zettel tag -> Parser -> Denote file creation
-}
data Zettel = Zettel
    { zettelSlug :: Text
    , zettelContent :: Text
    , zettelContinuation :: [Text]
    , zettelKeywords :: [Text]
    , zettelType :: ZettelType
    }
    deriving (Eq, Show, Generic)

{- | Types of zettel entries (simplified to single type)
@test-spec: ZETTLE.md#parsing
@implements: ZETTLE.md#syntax-design
-}
data ZettelType
    = ZettelNote -- #z:slug - zettel note (can evolve from fleeting to permanent)
    deriving (Eq, Show, Generic)

{- | Determine if a task should be synced to CalDAV
Only sync actionable items from today: open tasks, priority, scheduled, events, completed
Don't sync: notes, ideas, migrated, or tasks from other dates
@user-story: "I only want to see today's tasks in my calendar app"
@data-flow: Task -> check bullet type -> check if date == today -> sync decision
-}
shouldSyncTask :: Day -> Task -> Bool
shouldSyncTask today task =
    taskDate task == today && case taskBullet task of
        Open -> True -- . tasks to do
        Completed -> True -- x completed tasks
        Priority -> True -- ! urgent tasks
        Scheduled -> True -- < scheduled tasks
        Event -> True -- o events/appointments
        Shopping -> True -- $ shopping items to buy
        Idea -> False
        -- \* ideas/future items don't sync
        Migrated -> False -- > migrated tasks don't sync
