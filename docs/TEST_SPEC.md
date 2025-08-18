# Mind Goblin Test Specification

## Test Suite Overview

All tests enumerated from README.md design document. Each test includes a narrative explaining the user story and data flow.

## 1. Parser Module Tests

### 1.1 Bullet Recognition Tests

**Narrative**: Users type different bullet symbols to categorize their entries. The parser must recognize each symbol and map it to the correct entry type.

```haskell
-- Test: Parse open task bullet
-- User Story: "I type • to mark something I need to do"
-- Data Flow: "• Task" -> lexer -> '•' token -> Open bullet type
-- Input: "• Task"
-- Expected: Bullet Open

-- Test: Parse completed task bullet  
-- User Story: "I change • to × when I finish a task"
-- Data Flow: "× Task" -> lexer -> '×' token -> Completed bullet type
-- Input: "× Task"
-- Expected: Bullet Completed

-- Test: Parse migrated task bullet
-- User Story: "I use > to show I've moved this task to another day"
-- Data Flow: "> Task" -> lexer -> '>' token -> Migrated bullet type
-- Input: "> Task"
-- Expected: Bullet Migrated

-- Test: Parse scheduled task bullet
-- User Story: "I use < for tasks that have a specific time/date"
-- Data Flow: "< Meeting 2pm" -> lexer -> '<' token -> Scheduled bullet type
-- Input: "< Task"
-- Expected: Bullet Scheduled

-- Test: Parse note bullet
-- User Story: "I use − to capture thoughts that aren't tasks"
-- Data Flow: "− Note" -> lexer -> '−' token -> Note bullet type
-- Input: "− Note"
-- Expected: Bullet Note

-- Test: Parse priority bullet
-- User Story: "I use ! to mark urgent tasks that need immediate attention"
-- Data Flow: "! Task" -> lexer -> '!' token -> Priority bullet type
-- Input: "! Task"
-- Expected: Bullet Priority

-- Test: Parse idea bullet
-- User Story: "I use * to capture ideas for future consideration"
-- Data Flow: "* Idea" -> lexer -> '*' token -> Idea bullet type
-- Input: "* Idea"
-- Expected: Bullet Idea

-- Test: Parse event bullet
-- User Story: "I use ○ to mark events or appointments"
-- Data Flow: "○ Event" -> lexer -> '○' token -> Event bullet type
-- Input: "○ Event"
-- Expected: Bullet Event

-- Test: Invalid bullet character
-- User Story: "If I type something else, it shouldn't be treated as a task"
-- Data Flow: "# Task" -> lexer -> '#' not in bullet set -> ParseError
-- Input: "# Task"
-- Expected: ParseError
```

### 1.2 Task Parsing Tests

**Narrative**: Tasks are the core unit of work. They combine bullets, text, contexts, dates, and notes into a structured format that can be synced.

```haskell
-- Test: Single-line task
-- User Story: "I write a simple task on one line"
-- Data Flow: "• Buy milk" -> bullet parser -> text parser -> Task record created
-- Input: "• Buy milk"
-- Expected: Task { bullet = Open, text = "Buy milk", contexts = [], due = Nothing, notes = [], uid = Nothing }

-- Test: Task with single context
-- User Story: "I add @store to remember where to do this task"
-- Data Flow: "Buy milk @store" -> text parser -> @ symbol found -> context extracted
-- Input: "• Buy milk @store"
-- Expected: Task { contexts = ["store"] }

-- Test: Task with multiple contexts
-- User Story: "I tag tasks with multiple contexts for better filtering"
-- Data Flow: "@calls @urgent" -> scan for @ -> extract each word after @ -> context list
-- Input: "• Call Bob @calls @urgent"
-- Expected: Task { contexts = ["calls", "urgent"] }

-- Test: Task with due date
-- User Story: "I add Due: dates to track deadlines"
-- Data Flow: "Due: 2025-08-20" -> keyword "Due:" found -> date parser -> Date value
-- Input: "• Submit report Due: 2025-08-20"
-- Expected: Task { due = Just (Date 2025 08 20) }

-- Test: Task with continuation lines
-- User Story: "I add notes on indented lines below the task"
-- Data Flow: Line 1 (task) -> newline -> indent detected -> collect as notes
-- Input: "• Research topic\n  Check library\n  Read papers"
-- Expected: Task { notes = ["Check library", "Read papers"] }

-- Test: Task with UID comment
-- User Story: "The system adds invisible UIDs for sync tracking"
-- Data Flow: "<!-- UID:xxx -->" -> HTML comment parser -> extract UID value
-- Input: "• Task <!-- UID:550e8400-e29b-41d4-a716-446655440000 -->"
-- Expected: Task { uid = Just "550e8400-e29b-41d4-a716-446655440000" }

-- Test: Empty lines between tasks
-- User Story: "I use blank lines to visually separate tasks"
-- Data Flow: Task 1 -> empty line (skip) -> Task 2 -> list of tasks
-- Input: ". Task 1\n\n. Task 2"
-- Expected: [Task "Task 1", Task "Task 2"]

-- Test: Freeform notes are ignored
-- User Story: "Non-bulleted text is documentation only, not synced"
-- Data Flow: Freeform text -> parser -> skip (no task created)
-- Input: "Some documentation text"
-- Expected: No task created

-- Test: Mixed bullets and freeform
-- User Story: "Only bulleted items become tasks, freeform is preserved but ignored"
-- Data Flow: ". Task" -> Task created, "Notes" -> skipped
-- Input: ". Buy milk\nNotes about shopping\n. Call mom"
-- Expected: [Task "Buy milk", Task "Call mom"] (2 tasks, notes ignored)
```

### 1.3 Date Section Tests

**Narrative**: The todo.txt file is organized by date. Each date starts a new section where that day's tasks are logged.

```haskell
-- Test: Valid date header
-- User Story: "I start each day with the date in YYYY-MM-DD format"
-- Data Flow: "2025-08-16" -> date parser -> Date record -> new section started
-- Input: "2025-08-16\n• Task"
-- Expected: DateSection { date = Date 2025 08 16, entries = [Task] }

-- Test: Invalid date format
-- User Story: "The system rejects dates in wrong format to maintain consistency"
-- Data Flow: "08/16/2025" -> date parser -> format mismatch -> error
-- Input: "08/16/2025\n• Task"
-- Expected: ParseError "Invalid date format"

-- Test: Multiple date sections
-- User Story: "My file contains many days of tasks in chronological order"
-- Data Flow: Date 1 -> tasks -> Date 2 -> tasks -> list of sections
-- Input: "2025-08-16\n• Task 1\n2025-08-17\n• Task 2"
-- Expected: [DateSection 2025-08-16, DateSection 2025-08-17]

-- Test: Tasks without date section
-- User Story: "Tasks must be under a date for proper tracking"
-- Data Flow: No date found -> task parser -> error (orphaned task)
-- Input: "• Orphaned task"
-- Expected: ParseError "No date section"
```

### 1.4 Context Extraction Tests

**Narrative**: Contexts (GTD methodology) help categorize tasks by location, tool, or situation. They're marked with @ symbols.

```haskell
-- Test: Context at end of line
-- User Story: "I add @computer to tasks I can only do at my computer"
-- Data Flow: "Task @computer" -> scan right to left -> @ found -> extract word
-- Input: "Task @computer"
-- Expected: ["computer"]

-- Test: Context in middle should not match
-- User Story: "Email addresses shouldn't be treated as contexts"
-- Data Flow: "bob@example.com" -> @ in middle of word -> skip
-- Input: "Email bob@example.com"
-- Expected: []

-- Test: Multiple contexts
-- User Story: "I use multiple contexts to create richer categorization"
-- Data Flow: Multiple @ symbols -> extract each -> build context list
-- Input: "Task @home @urgent @computer"
-- Expected: ["home", "urgent", "computer"]

-- Test: Contexts with valid characters
-- User Story: "Contexts can have hyphens and underscores"
-- Data Flow: @home-office -> @ found -> extract until space/EOL
-- Input: "Task @home-office @high_priority"
-- Expected: ["home-office", "high_priority"]

-- Test: Invalid contexts with spaces
-- User Story: "Contexts end at spaces to avoid false matches"
-- Data Flow: "@invalid context" -> @ found -> extract "invalid" -> "context" is separate
-- Input: "Task @invalid context"
-- Expected: ["invalid"] -- "context" is separate word
```

### 1.5 Due Date Parsing Tests

**Narrative**: Due dates help track deadlines. They're marked with "Due:" followed by a date.

```haskell
-- Test: Valid due date
-- User Story: "I mark deadlines with Due: YYYY-MM-DD"
-- Data Flow: "Due: 2025-08-20" -> keyword match -> date parser -> Date value
-- Input: "Due: 2025-08-20"
-- Expected: Just (Date 2025 08 20)

-- Test: Due date with time (ignore time)
-- User Story: "Times are ignored since we only track dates"
-- Data Flow: "Due: 2025-08-20 14:30" -> extract date part -> ignore time
-- Input: "Due: 2025-08-20 14:30"
-- Expected: Just (Date 2025 08 20)

-- Test: Invalid due date format
-- User Story: "Natural language dates aren't supported (yet)"
-- Data Flow: "Due: tomorrow" -> date parser fails -> Nothing
-- Input: "Due: tomorrow"
-- Expected: Nothing

-- Test: Past due date
-- User Story: "Past dates are valid for overdue task tracking"
-- Data Flow: "Due: 2020-01-01" -> parse succeeds -> date in past is OK
-- Input: "Due: 2020-01-01"
-- Expected: Just (Date 2020 01 01) -- Valid but in past
```

## 2. VTODO Generation Tests

### 2.1 ICS File Generation Tests

**Narrative**: Each task gets converted to an iCalendar file in the vdir directory. vdirsyncer then syncs these files with CalDAV servers.

```haskell
-- Test: Create .ics file with correct name
-- User Story: "Each task becomes a separate .ics file named by its UID"
-- Data Flow: Task with UID -> generate filename -> write to vdir/tasks/UID.ics
-- Input: Task with UID "550e8400"
-- Expected: File "~/.config/mg/vdir/tasks/550e8400.ics" exists

-- Test: Generate new UID for task without one
-- User Story: "New tasks get a unique ID for tracking"
-- Data Flow: Task without UID -> UUID generator -> add UID to task -> create file
-- Input: Task without UID
-- Expected: Valid UUID v4 generated

-- Test: Valid VTODO structure
-- User Story: "Files must be valid iCalendar format for compatibility"
-- Data Flow: Task -> VTODO generator -> wrap in VCALENDAR -> valid .ics
-- Expected: Contains BEGIN:VCALENDAR, BEGIN:VTODO, END:VTODO, END:VCALENDAR

-- Test: RFC5545 compliance
-- User Story: "Files must comply with iCalendar standard"
-- Data Flow: Required fields added -> VERSION, PRODID -> RFC5545 valid
-- Expected: VERSION:2.0, PRODID present
```

### 2.2 VTODO Content Tests

**Narrative**: Task properties map to specific VTODO fields according to iCalendar standards.

```haskell
-- Test: Basic task to VTODO
-- User Story: "My task text becomes the calendar item summary"
-- Data Flow: Task "Buy milk" -> SUMMARY field -> STATUS:NEEDS-ACTION (open)
-- Input: Task "Buy milk"
-- Expected: SUMMARY:Buy milk, STATUS:NEEDS-ACTION

-- Test: Priority task
-- User Story: "! tasks show as high priority in calendar apps"
-- Data Flow: Priority bullet -> PRIORITY:1 (highest) in VTODO
-- Input: Task with Priority bullet
-- Expected: PRIORITY:1

-- Test: Contexts to CATEGORIES
-- User Story: "My @contexts become calendar categories for filtering"
-- Data Flow: ["home", "urgent"] -> join with comma -> CATEGORIES field
-- Input: Task with ["home", "urgent"]
-- Expected: CATEGORIES:home,urgent

-- Test: Due date
-- User Story: "Due dates sync to calendar apps for deadline tracking"
-- Data Flow: Date 2025-08-20 -> format as YYYYMMDD -> DUE field
-- Input: Task with Due: 2025-08-20
-- Expected: DUE:20250820

-- Test: Notes to DESCRIPTION
-- User Story: "My indented notes become the task description"
-- Data Flow: Note lines -> join with \n -> DESCRIPTION field
-- Input: Task with notes ["Line 1", "Line 2"]
-- Expected: DESCRIPTION:Line 1\nLine 2

-- Test: Escape special characters
-- User Story: "Commas and special chars are escaped per iCalendar rules"
-- Data Flow: "Meeting, review" -> escape comma -> "Meeting\, review"
-- Input: Task "Meeting, review"
-- Expected: SUMMARY:Meeting\, review

-- Test: Line folding for long text
-- User Story: "Long lines are folded at 75 chars per iCalendar spec"
-- Data Flow: 100+ char line -> fold at 75 -> continuation with space
-- Input: Task with 100+ char summary
-- Expected: Lines folded at 75 chars
```

### 2.3 ICS File Update Tests

**Narrative**: When tasks change, their corresponding .ics files are updated while preserving sync metadata.

```haskell
-- Test: Update existing .ics file
-- User Story: "Editing a task updates its calendar entry"
-- Data Flow: Modified task -> find existing .ics by UID -> overwrite content
-- Input: Modified task with same UID
-- Expected: File updated, UID preserved

-- Test: Atomic write with temp file
-- User Story: "File updates are atomic to prevent corruption"
-- Data Flow: Write to .tmp -> fsync -> rename to .ics -> atomic update
-- Expected: Write to .tmp, then rename

-- Test: Preserve file permissions
-- User Story: "File permissions don't change on update"
-- Data Flow: Read perms -> write new content -> restore perms
-- Expected: Same permissions as original
```

## 3. vdir Sync Tests

### 3.1 vdir Reading Tests

**Narrative**: The vdir directory contains .ics files that may have been modified by vdirsyncer after syncing with CalDAV servers.

```haskell
-- Test: Parse all .ics files
-- User Story: "All calendar files in vdir are checked for updates"
-- Data Flow: List vdir/*.ics -> parse each -> extract VTODO data
-- Input: Directory with 5 .ics files
-- Expected: 5 VTODOs parsed

-- Test: Extract completion status
-- User Story: "Completed tasks in calendar apps are detected"
-- Data Flow: .ics file -> parse VTODO -> STATUS:COMPLETED found -> marked done
-- Input: VTODO with STATUS:COMPLETED
-- Expected: Task marked as completed

-- Test: Handle malformed .ics
-- User Story: "Bad files don't crash the sync process"
-- Data Flow: Invalid .ics -> parser fails -> log error -> skip file
-- Input: Invalid .ics file
-- Expected: Skip file, log error

-- Test: Skip non-VTODO items
-- User Story: "Calendar events (VEVENT) are ignored"
-- Data Flow: .ics with VEVENT -> check type -> not VTODO -> skip
-- Input: .ics with VEVENT
-- Expected: Ignore VEVENT
```

### 3.2 Completion Detection Tests

**Narrative**: When tasks are marked complete in calendar apps, this status needs to be detected and reflected in todo.txt.

```haskell
-- Test: Detect STATUS:COMPLETED
-- User Story: "Tasks completed in my phone update in todo.txt"
-- Data Flow: VTODO -> STATUS field -> value is COMPLETED -> flag as done
-- Input: VTODO with STATUS:COMPLETED
-- Expected: Completion detected

-- Test: Match UID to task
-- User Story: "The right task gets marked complete"
-- Data Flow: UID from .ics -> search todo.txt for matching UID comment -> task found
-- Input: UID in .ics matches task UID
-- Expected: Correct task identified

-- Test: Handle PERCENT-COMPLETE
-- User Story: "Some calendar apps use percentage completion"
-- Data Flow: PERCENT-COMPLETE:100 -> 100% means done -> mark complete
-- Input: PERCENT-COMPLETE:100
-- Expected: Marked as completed

-- Test: Missing STATUS field
-- User Story: "Tasks without status are assumed incomplete"
-- Data Flow: No STATUS field -> default to NEEDS-ACTION -> not complete
-- Input: VTODO without STATUS
-- Expected: Assume NEEDS-ACTION
```

### 3.3 vdir Writing Tests

**Narrative**: Changes to todo.txt need to be reflected in the vdir for vdirsyncer to push to CalDAV.

```haskell
-- Test: Create new .ics for open tasks
-- User Story: "New tasks in todo.txt appear in my calendar"
-- Data Flow: New task -> generate UID -> create .ics in vdir
-- Input: Task without .ics file
-- Expected: New .ics created

-- Test: Update existing .ics
-- User Story: "Editing task text updates the calendar entry"
-- Data Flow: Task text changed -> find .ics by UID -> update SUMMARY
-- Input: Task text changed
-- Expected: .ics updated

-- Test: Handle vdirsyncer lock
-- User Story: "Don't interfere with active vdirsyncer operations"
-- Data Flow: Check for .lock -> if exists, wait or abort -> proceed when clear
-- Input: .lock file present
-- Expected: Wait or fail gracefully
```

## 4. File Update Tests

### 4.1 In-place Update Tests

**Narrative**: When tasks are completed externally, the bullet in todo.txt changes from • to × while preserving everything else.

```haskell
-- Test: Change bullet to completed
-- User Story: "Completed tasks show as × in my todo.txt"
-- Data Flow: Line with • -> completion detected -> replace • with × -> write line
-- Input: "• Task" marked complete
-- Expected: "× Task"

-- Test: Preserve task text
-- User Story: "Only the bullet changes, nothing else"
-- Data Flow: "• Buy milk @store" -> × + " Buy milk @store" -> exact preservation
-- Input: "• Buy milk @store"
-- Expected: "× Buy milk @store"

-- Test: Preserve indentation
-- User Story: "Indented tasks stay indented"
-- Data Flow: Count leading spaces -> change bullet -> restore spaces
-- Input: "  • Subtask"
-- Expected: "  × Subtask"

-- Test: Add UID comment
-- User Story: "UIDs are added invisibly for sync tracking"
-- Data Flow: Task without UID -> generate -> append as HTML comment
-- Input: Task without UID
-- Expected: "× Task <!-- UID:generated-uid -->"

-- Test: Preserve existing UID
-- User Story: "UIDs never change once assigned"
-- Data Flow: Existing UID comment -> keep unchanged -> preserve sync state
-- Input: Task with UID comment
-- Expected: UID unchanged
```

### 4.2 File Safety Tests

**Narrative**: File operations must be safe, atomic, and preserve user data.

```haskell
-- Test: Create backup before changes
-- User Story: "My todo.txt is backed up before any changes"
-- Data Flow: Copy todo.txt -> todo.txt.backup -> proceed with updates
-- Expected: todo.txt.backup created

-- Test: Atomic write
-- User Story: "File updates never leave partial data"
-- Data Flow: Write todo.txt.tmp -> fsync -> rename to todo.txt -> atomic
-- Expected: Write to .tmp, rename

-- Test: Handle concurrent access
-- User Story: "Multiple mg processes don't corrupt the file"
-- Data Flow: Acquire lock -> make changes -> release lock -> exclusive access
-- Expected: File locking used

-- Test: Preserve permissions
-- User Story: "File permissions don't change"
-- Data Flow: stat() original -> write new -> chmod() to match
-- Expected: Same as original

-- Test: Handle missing todo.txt
-- User Story: "mg creates todo.txt if it doesn't exist"
-- Data Flow: File not found -> create empty -> add today's date
-- Expected: Create if not exists
```

## 5. Integration Tests

### 5.1 Full Sync Cycle Tests

**Narrative**: The complete flow from creating a task to marking it complete via CalDAV.

```haskell
-- Test: Complete sync flow
-- User Story: "I add a task, sync it, complete it on my phone, sync again"
-- Data Flow:
--   1. Add "• Task" to todo.txt
--   2. mg push -> creates .ics with UID
--   3. vdirsyncer sync -> uploads to CalDAV
--   4. Complete task in calendar app
--   5. vdirsyncer sync -> downloads update
--   6. mg pull -> detects STATUS:COMPLETED
--   7. Updates todo.txt to "× Task"
-- Expected: Task shows as × in todo.txt

-- Test: Multiple tasks
-- User Story: "I can sync many tasks at once"
-- Data Flow: 5 tasks -> 2 completed externally -> pull -> 2 bullets change
-- Input: 5 tasks, 2 completed
-- Expected: 2 bullets changed to ×

-- Test: Tasks across dates
-- User Story: "Tasks from different days all sync correctly"
-- Data Flow: Parse all dates -> process all tasks -> maintain date organization
-- Input: Tasks under different date headers
-- Expected: All processed correctly
```

### 5.2 vdirsyncer Integration Tests

**Narrative**: mg must work seamlessly with vdirsyncer for CalDAV operations.

```haskell
-- Test: Invoke vdirsyncer
-- User Story: "mg runs vdirsyncer to sync with my calendar"
-- Data Flow: spawn process -> "vdirsyncer sync" -> wait for completion
-- Command: vdirsyncer sync
-- Expected: Exit code 0

-- Test: Handle vdirsyncer errors
-- User Story: "Sync errors are reported clearly"
-- Data Flow: vdirsyncer fails -> capture stderr -> show user -> no corruption
-- Input: Invalid config
-- Expected: Error message, no file changes

-- Test: Parse vdirsyncer output
-- User Story: "I see what vdirsyncer is doing"
-- Data Flow: stdout/stderr -> parse progress -> display to user
-- Expected: Extract sync status

-- Test: Respect vdirsyncer locks
-- User Story: "mg doesn't interfere with running vdirsyncer"
-- Data Flow: Check for lock file -> if exists, wait -> proceed when clear
-- Input: vdirsyncer running
-- Expected: Wait or abort
```

### 5.3 Performance Tests

**Narrative**: The system must handle real-world usage with many tasks efficiently.

```haskell
-- Test: 1000 tasks
-- User Story: "Years of tasks don't slow down the system"
-- Data Flow: Parse 1000 tasks -> generate/update .ics files -> stay responsive
-- Expected: Process in <1 second

-- Test: Large file (10MB)
-- User Story: "My todo.txt grows over time without issues"
-- Data Flow: Stream processing -> don't load all in memory -> handle gracefully
-- Expected: Handle gracefully

-- Test: Many date sections (365)
-- User Story: "A year of daily entries works fine"
-- Data Flow: Parse each date -> maintain order -> process efficiently
-- Expected: Parse correctly
```

## 6. Edge Case Tests

### 6.1 Malformed Input Tests

**Narrative**: The parser must handle corrupted or unusual input gracefully.

```haskell
-- Test: Binary data
-- User Story: "Accidental binary data doesn't crash mg"
-- Data Flow: Binary bytes -> UTF-8 decoder -> fail gracefully -> skip line
-- Input: Binary bytes in file
-- Expected: Skip or error gracefully

-- Test: Invalid UTF-8
-- User Story: "Character encoding issues are handled"
-- Data Flow: Invalid sequences -> decoder error -> skip or replace
-- Input: Invalid byte sequences
-- Expected: Handle encoding error

-- Test: Long lines (>10KB)
-- User Story: "Accidentally pasted data doesn't break parsing"
-- Data Flow: Very long line -> buffer limit -> truncate or skip
-- Input: Single line >10KB
-- Expected: Truncate or error

-- Test: Missing newline at EOF
-- User Story: "Files without final newline work"
-- Data Flow: EOF without \n -> add virtual newline -> parse normally
-- Expected: Handle gracefully
```

### 6.2 vdir Issue Tests

**Narrative**: Problems with the vdir directory structure must be handled robustly.

```haskell
-- Test: Missing vdir directory
-- User Story: "mg creates directories as needed"
-- Data Flow: vdir not found -> mkdir -p -> create structure
-- Expected: Create directory

-- Test: Read-only vdir
-- User Story: "Permission issues are reported clearly"
-- Data Flow: Write fails -> EACCES -> clear error message
-- Expected: Error with clear message

-- Test: Corrupted .ics files
-- User Story: "Bad calendar files don't stop sync"
-- Data Flow: Parse error -> log warning -> skip file -> continue
-- Expected: Skip bad files

-- Test: Duplicate UIDs
-- User Story: "UID conflicts are detected and handled"
-- Data Flow: Same UID twice -> detect conflict -> resolution strategy
-- Expected: Handle or error
```

### 6.3 Sync Conflict Tests

**Narrative**: Network and synchronization issues must not corrupt data.

```haskell
-- Test: Task modified during sync
-- User Story: "Concurrent edits don't lose data"
-- Data Flow: Read file -> sync starts -> file changes -> detect -> preserve local
-- Expected: Preserve local changes

-- Test: Network failure
-- User Story: "Network issues don't corrupt local data"
-- Data Flow: vdirsyncer fails -> network error -> local files unchanged
-- Expected: Graceful degradation

-- Test: Auth failure
-- User Story: "Login problems are clearly reported"
-- Data Flow: 401/403 error -> parse vdirsyncer output -> show user
-- Expected: Clear error message
```

## Test Implementation Strategy

Each test narrative shows:
1. **User Story**: Why this matters to the user
2. **Data Flow**: How data moves through the system
3. **Input/Output**: Concrete test values
4. **Expected Behavior**: What success looks like

This ensures tests are meaningful, not just technical exercises.