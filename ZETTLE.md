# Zettelkasten Seeding Design

## Overview

Extend Mind Goblin to support zettelkasten seeding - transforming fleeting thoughts captured in daily bullet journals into atomic denote-formatted notes. This integrates seamlessly with `mg sync` to create a unified knowledge capture workflow.

## Philosophy

**Capture → Process → Connect**

1. **Capture**: Fleeting thoughts tagged in daily todo.txt during bullet journaling
2. **Process**: `mg sync` automatically seeds zettels into denote format
3. **Connect**: Expanded zettels link back for knowledge graph development

## Syntax Design

### Zettel Tags
Special tags in todo.txt that mark content for zettel seeding:

```
2025-08-21
• Meeting with team @work
#zettel:atomic-design Atomic design principle applies to data structures too
  - Each component should have single responsibility
  - Composition over inheritance in our API design

#z:knowledge-graphs Personal knowledge management needs better linking

#idea:mg-extension What if mg could seed a zettelkasten?
  - Integrate with denote format
  - Use vjournal for future CalDAV sync
```

### Tag Variants
- `#zettel:SLUG` - Full zettelkasten entry
- `#z:SLUG` - Short form for quick capture
- `#idea:SLUG` - Ideas for future development

### Slug Requirements
- Lowercase letters, numbers, hyphens only
- Max 50 characters
- Becomes part of denote filename

## Integration with mg sync

### Unified Workflow
```bash
mg sync
```
Now handles:
1. **Tasks** → CalDAV VTODO sync (existing)
2. **Events** → CalDAV VEVENT sync (existing) 
3. **Zettels** → Denote file creation (NEW)

Future: VJOURNAL CalDAV sync for zettel content

### Processing Order
1. Parse todo.txt for all content types
2. Sync tasks/events with CalDAV (existing logic)
3. Extract and seed zettels to `~/doc/notes/`
4. Optionally update todo.txt with links to created zettels

## Denote Format Output

### File Naming
Following denote convention:
`TIMESTAMP--SLUG__KEYWORDS.txt`

Example: `20250821T143022--atomic-design__software-architecture_design-principles.txt`

### File Content Structure
```
title:      Atomic Design for Data Structures
date:       2025-08-21T14:30:22
filetags:   software-architecture design-principles  
identifier: 20250821T143022
source:     mg-bullet-journal

Atomic design principle applies to data structures too

- Each component should have single responsibility
- Composition over inheritance in our API design

---
Seeded from: ~/todo.txt (2025-08-21)
Original context: @work meeting
```

### Keyword Generation
- Extract from original @contexts
- Infer from slug components  
- Add semantic tags based on content

## File System Structure

### Default Paths
- **Zettel directory**: `~/doc/notes/` (configurable)
- **Backup location**: `~/.config/mg/zettel-backups/`

### Directory Creation
mg automatically creates directories if they don't exist.

## Data Types Extension

### Core Types
```haskell
-- Extend existing Task type
data Task = Task
  { taskDate :: Day
  , taskBullet :: Bullet
  , taskText :: Text
  , taskContexts :: [Context]
  , taskDue :: Maybe Day
  , taskNotes :: [Text]
  , taskUid :: Maybe Text
  , taskEventTime :: Maybe Text
  , taskZettel :: Maybe Zettel  -- NEW
  }

-- New zettel types  
data Zettel = Zettel
  { zettelSlug :: Text
  , zettelContent :: Text
  , zettelContinuation :: [Text]
  , zettelKeywords :: [Text]
  , zettelType :: ZettelType
  } deriving (Eq, Show)

data ZettelType 
  = ZettelFull    -- #zettel:slug
  | ZettelShort   -- #z:slug  
  | ZettelIdea    -- #idea:slug
  deriving (Eq, Show)
```

## CLI Commands

### Primary Command (Integrated)
```bash
mg sync              # Handles tasks, events, AND zettels
mg sync --dry-run    # Preview all sync operations including zettels
```

### Zettel-Specific Commands
```bash
mg zettels list         # Show all zettel tags in current todo.txt
mg zettels seed         # Seed zettels only (no task/event sync)
mg zettels seed --dry-run  # Preview zettel seeding
```

### Configuration Commands
```bash
mg config set zettel.directory ~/notes     # Set custom zettel directory
mg config set zettel.link-back true        # Replace tags with links
mg config set zettel.keywords-from-context true  # Use @contexts as keywords
```

## Processing Logic

### Parse Phase
1. Scan todo.txt for zettel tags (`#zettel:`, `#z:`, `#idea:`)
2. Extract content (current line + indented continuation)
3. Parse slug and validate format
4. Generate keywords from contexts and content

### Seed Phase  
1. Create denote identifier (timestamp)
2. Generate filename from slug and keywords
3. Create file in `~/doc/notes/`
4. Write denote front matter + content
5. Optionally replace original tag with link

### Link-Back Option
When enabled, original todo.txt entry becomes:
```
• Meeting with team @work
→ [[20250821T143022--atomic-design][Atomic Design for Data Structures]]
```

## Configuration

### Default Config (~/.config/mg/config)
```toml
[zettel]
enabled = true
directory = "~/doc/notes"
link_back = false
keywords_from_context = true
backup_original = true

[zettel.formats]
full_tag = "#zettel:"
short_tag = "#z:"  
idea_tag = "#idea:"
```

## Future: CalDAV Integration

### VJOURNAL Support
Once CalDAV servers better support VJOURNAL:
- Sync zettel content as VJOURNAL entries
- Maintain bidirectional sync like tasks
- Enable cross-device zettel access

### Metadata Sync
- Zettel keywords → VJOURNAL categories
- Creation date → VJOURNAL dtstart
- Content → VJOURNAL description

## Error Handling

### Validation Errors
- Invalid slug format → skip with warning
- Directory permission issues → clear error message
- Duplicate filenames → append counter or skip

### Recovery
- Backup original todo.txt before processing
- Atomic file operations for zettel creation
- Rollback capability if seeding fails

## Test Strategy

Following mg's test-first development:

### Parser Tests (Phase 1)
- Zettel tag recognition
- Slug validation
- Content extraction with continuations
- Keyword generation

### File Creation Tests (Phase 2) 
- Denote filename generation
- Front matter formatting
- Directory creation
- File permissions

### Integration Tests (Phase 3)
- Full sync with zettel seeding
- Link-back functionality
- Configuration handling
- Error recovery

## Use Cases

### Daily Knowledge Capture
```
2025-08-21
• Team retrospective @work
#zettel:retrospective-insights Team dynamics affect code quality
  - Psychological safety enables better code reviews
  - Time pressure reduces thoughtful architecture
```
→ Creates: `20250821T091500--retrospective-insights__team-dynamics_code-quality.txt`

### Research Notes
```
#z:semantic-web Tim Berners-Lee's vision of machine-readable web
  - RDF as knowledge representation
  - Links between concepts, not just documents
```
→ Creates: `20250821T141200--semantic-web__knowledge-representation_rdf.txt`

### Project Ideas
```
#idea:personal-wiki Combine mg with static site generation
  - Zettels become wiki pages
  - Task history shows project evolution
```
→ Creates: `20250821T160300--personal-wiki__static-sites_project-management.txt`

## Benefits

### For Knowledge Workers
- Seamless capture during daily planning
- No context switching between bullet journal and zettelkasten
- Automatic organization with denote format

### For mg Users  
- Natural extension of existing workflow
- Unified sync command for all knowledge types
- Plain text approach maintains mg philosophy

### For Zettelkasten Practice
- Lower friction for fleeting note capture
- Consistent formatting and metadata
- Integration with existing note-taking systems

## Implementation Priority

### MVP (v1.0)
- Basic zettel tag parsing
- Denote file creation
- Integration with `mg sync`
- Simple keyword generation

### Enhanced (v1.1)
- Link-back functionality
- Configuration options
- Better keyword inference
- Validation and error handling

### Future (v2.0)
- CalDAV VJOURNAL sync
- Cross-reference detection
- Automatic tagging suggestions
- Integration with other PKM tools

---

This design extends mg's core mission: **maintaining sync between plain text workflows and structured knowledge systems**. Now that includes both calendar systems (CalDAV) and knowledge management (zettelkasten via denote).