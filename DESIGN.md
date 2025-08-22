# Mind Goblin Design

## Principles

1. **Single file**: All tasks in `~/todo.txt`
2. **Bullet journal notation**: Standard symbols for task types
3. **Minimal sync**: Push tasks, pull completion status only
4. **Historical record**: Complete log preserved in text file
5. **Plain text**: Human-readable, tool-agnostic format
6. **vdirsyncer integration**: Leverage existing CalDAV tooling

## File Format

### Structure
```
YYYY-MM-DD
<bullet> <task text> [<@context>...] [Due: YYYY-MM-DD]
<continuation lines indented with two spaces>
```

### Bullet Types
- `•` Open task
- `×` Completed task
- `>` Migrated task
- `<` Scheduled task
- `−` Note
- `!` Priority task
- `*` Idea
- `○` Event

### Context Tags
Tasks can include `@context` tags for categorization and filtering.

### Due Dates
Format: `Due: YYYY-MM-DD`

### Zettel Tags
Format: `#z:slug content` for zettelkasten integration.

## Data Flow

### Today-Only Sync
```
~/todo.txt → [Parse] → [Filter: today only] → [CalDAV] → Calendar App
~/todo.txt ← [Update completion status] ← [CalDAV] ← Calendar App
```

### Historical Preservation
- Complete todo.txt file maintains all dates and entries
- Calendar app shows only today's actionable items
- Completion status syncs bidirectionally
- Notes and non-actionable content stays local

### Zettel Extraction
```
~/todo.txt → [Parse #z: tags] → [Generate denote files] → ~/doc/notes/
```

## Architecture

### Core Modules
- **Parser**: Bullet journal notation parsing
- **Types**: Core data structures (Task, Bullet, Context, Zettel)
- **VTodo**: iCalendar VTODO generation
- **VDir**: vdir file operations
- **Sync**: Orchestration and coordination
- **FileOps**: Safe file operations
- **VDirSyncer**: Subprocess management
- **Zettel**: Zettelkasten integration

### External Dependencies
- **vdirsyncer**: CalDAV protocol handling
- **Calendar service**: Google Calendar, iCloud, FastMail, etc.

## Synchronization Logic

### Push Phase
1. Parse `~/todo.txt`
2. Filter for today's actionable tasks
3. Generate VTODO/VEVENT for each task
4. Write to vdir directory
5. Run `vdirsyncer sync`

### Pull Phase
1. Run `vdirsyncer sync`
2. Read vdir directory
3. Identify completed tasks
4. Update completion status in `~/todo.txt`

### Zettel Phase (integrated with sync)
1. Parse `~/todo.txt` for `#z:` tags
2. Generate denote-format files
3. Write to `~/doc/notes/` (skip if exists)

## Task States

### Local States (in todo.txt)
- Open (•): Needs action
- Completed (×): Done
- Priority (!): Urgent
- Scheduled (<): Timed
- Event (○): Appointment
- Idea (*): Future consideration
- Migrated (>): Moved to different date
- Note (−): Information only

### CalDAV Mapping
- Open/Priority/Scheduled → NEEDS-ACTION
- Completed → COMPLETED
- Event → VEVENT instead of VTODO

### Sync Rules
- Only today's tasks sync to calendar
- Only actionable tasks sync (not ideas, notes, migrated)
- Completion status syncs bidirectionally
- Calendar changes don't modify task text or contexts

## Error Handling

### Parse Errors
- Invalid date formats: skip section with warning
- Malformed tasks: skip line with warning
- Continue processing remaining content

### Sync Errors
- vdirsyncer failures: abort with error message
- Network issues: retry with exponential backoff
- Calendar service errors: surface to user

### File Operations
- Atomic writes to prevent corruption
- Backup original before modifications
- Rollback on failure

## Testing Strategy

### Unit Tests
- Parser validation for all bullet types
- VTODO generation correctness
- Date handling and filtering
- Context extraction

### Integration Tests
- Full sync cycle simulation
- vdirsyncer interaction
- File modification scenarios
- Error condition handling

### Property Tests
- Round-trip parsing (parse → serialize → parse)
- UID determinism
- Date arithmetic correctness

## Performance Considerations

### File Size
- Large todo.txt files (10k+ entries) parse in <100ms
- Today-only filtering keeps calendar sync lightweight
- Incremental parsing for watch mode

### Memory Usage
- Stream-based parsing for large files
- Minimal data structure overhead
- Lazy evaluation where possible

### Network Usage
- Only today's tasks transmitted
- Compression handled by vdirsyncer
- Differential sync via vdirsyncer's conflict resolution