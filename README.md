# Mind Goblin

Bullet journal task synchronization with CalDAV via vdirsyncer.

## Overview

Mind Goblin (`mg`) synchronizes plain text bullet journal files with CalDAV calendar services. Changes made in either the local text file or calendar applications are propagated bidirectionally.

The parser supports standard bullet journal notation and generates RFC 5545-compliant iCalendar data. All CalDAV communication is handled through vdirsyncer.

## Installation

### Evaluation
```bash
nix run github:daytimeforninja/mindgoblin -- init
nix run github:daytimeforninja/mindgoblin -- sync
```

### Installation
```bash
nix profile install github:daytimeforninja/mindgoblin
mg init && mg sync
```

## Core Features

### Bullet Journal Notation
Supported symbols:
- `.` - Open tasks
- `x` - Completed tasks 
- `!` - Priority tasks
- `$` - Shopping items
- `o` - Events
- `<` - Scheduled tasks
- `>` - Migrated tasks
- `*` - Ideas

Freeform text (lines without bullets) is preserved locally but not synced.

### Synchronization
Bidirectional sync between local text files and CalDAV endpoints. Changes in either location are propagated on the next sync cycle.

### CalDAV Compliance
RFC 5545 (iCalendar) and RFC 4791 (CalDAV) compliant.

### Zettelkasten Integration
Use `#z:slug` tags to extract notes to denote-format files:

```
2025-08-17
. Review quarterly plans @work
#z:atomic-habits Small changes compound for massive results over time
  - Environment design beats willpower
  - Focus on systems, not just goals
```

`mg sync` processes tasks for CalDAV and zettel tags for denote files in `~/doc/notes/`.

### Vdirsyncer Integration
Uses vdirsyncer for CalDAV communication.

## File Format

### Structure
Date-sectioned plaintext with bullet journal notation:

```
2025-08-17
. Buy groceries @errands
$ Milk and bread @groceries
! Call dentist @urgent Due: 2025-08-18
x Finished project @work
Meeting notes: discussed Q4 plans
- Reviewed roadmap priorities  
- Customer feedback positive
- Need mobile app features
```

### Date Sections
Files organized by date headers (YYYY-MM-DD format).

### Context Tags
Use `@context` notation for categorization. Multiple contexts per task supported.

### Due Dates
Format: `Due: YYYY-MM-DD`

### Synchronization Behavior
`mg sync` performs bidirectional synchronization with today-only filtering:

- Only today's tasks sync to calendar apps
- Complete history remains in todo.txt
- Completion status syncs bidirectionally
- Calendar shows actionable items, text file preserves history

## Command Reference

### Primary Commands

```bash
mg sync    # Bidirectional sync with CalDAV and zettel extraction
mg push    # Upload tasks to calendar (one-way)
mg pull    # Download task changes from calendar (one-way)
mg zettel  # Extract #z: tags to denote files
mg list    # Show today's tasks by priority
mg init    # Setup configuration and vdirsyncer
mg stats   # Task statistics
mg watch   # Auto-sync on file changes
```

### Command Details

#### `mg sync`
1. Upload local tasks to calendar
2. Download task changes from calendar
3. Extract zettel tags to denote files
4. Run vdirsyncer sync
5. Update local file with remote changes

#### `mg zettel`
Extracts `#z:slug` tags to denote-format files:
- Scans todo.txt for zettel tags
- Creates timestamped files with metadata
- Skips existing files (no overwrites)
- Options: `--file`, `--notes-dir`, `--dry-run`

**Usage examples:**
```bash
mg zettel                              # Extract from ~/todo.txt to ~/doc/notes
mg zettel --dry-run                    # Preview what would be extracted
mg zettel --file work.txt              # Extract from custom file
mg zettel --notes-dir ~/notes          # Custom output directory
```

#### `mg init`
Setup configuration:
- Create directory structures
- Validate vdirsyncer config
- Calendar endpoint discovery
- Initial sync state

#### `mg list`
Shows tasks by priority (Priority → Open → Events → Completed):
- Default: today's tasks only
- `--all`: show all dates
- `--completed`: include completed tasks  
- `--context work`: filter by context
- `--file`: specify custom file

**Usage examples:**
```bash
mg list                           # Show today's tasks by priority
mg list --all                     # Show all tasks from all dates
mg list --completed               # Include completed tasks
mg list --context work            # Show only @work tasks
mg list --file ~/work.txt --all   # Use custom file and show all tasks
```

**Output format:**
```
🔥 Priority Tasks:
! Fix production bug @urgent @computer Due: 2025-08-21

📋 Open Tasks:
. Review code changes @computer

🛒 Shopping:
$ Milk and bread @groceries

📅 Events:
o Team standup 10am @meetings

📊 Showing 4 tasks (today only)
```

## Setup and Configuration

### Prerequisites
Mind Goblin requires vdirsyncer for CalDAV communication. Install vdirsyncer through your system package manager or using pip:

```bash
pip install vdirsyncer
```

### Initial Configuration
Execute the following sequence to establish a complete working system:

1. **Install vdirsyncer** - Required for CalDAV protocol communication
2. **Configure calendar discovery:** `vdirsyncer discover tasks` - Establishes authentication and endpoint discovery
3. **Initialize Mind Goblin:** `mg init` - Creates configuration files and directory structures
4. **Execute initial sync:** `mg sync` - Performs first bidirectional synchronization

### Directory Structure
Mind Goblin creates and maintains the following directory structure:
```
~/.config/mg/
├── config              # Main configuration file
├── vdir/               # Local CalDAV cache directory
│   └── tasks/          # Individual task files in .ics format
└── cache/              # Backup and temporary files
```

### Configuration Management
The system automatically generates configuration files optimized for most use cases. Advanced users may customize behavior through the `~/.config/mg/config` file following standard TOML syntax.

## Troubleshooting

### Common Issues and Resolutions

#### Synchronization Failures
**Symptom:** Tasks are not appearing in calendar applications after sync
**Resolution:** Verify vdirsyncer operation with `vdirsyncer sync tasks`. Check network connectivity and authentication credentials.

#### Duplicate Task Entries  
**Symptom:** Identical tasks appearing multiple times
**Resolution:** Upgrade to version 0.1.3.0 or later. Execute `mg pull` to resolve existing duplicates.

#### Date Format Errors
**Symptom:** Parser errors related to date sections
**Resolution:** Ensure all date headers follow ISO 8601 format: `YYYY-MM-DD` (example: 2025-08-17). Verify no invalid dates such as February 30th.

#### File Lock Errors
**Symptom:** "Device or resource busy" errors during sync
**Resolution:** Ensure no other applications have the todo.txt file open. Restart the sync operation.

### Diagnostic Commands
```bash
mg stats                    # Display system status and task counts
mg list                     # Show today's actionable tasks by priority  
mg list --all               # Show all tasks across all dates
vdirsyncer sync tasks      # Test direct vdirsyncer functionality
mg init --force            # Reset configuration (destructive)
```

## Additional Documentation

### Reference Materials
- [Design Document](DESIGN.md) - Comprehensive architectural overview and implementation details
- [Installation Guide](INSTALL.md) - Advanced installation scenarios and platform-specific instructions

### Technical Specifications
- [RFC 5545](https://tools.ietf.org/html/rfc5545) - iCalendar specification
- [RFC 4791](https://tools.ietf.org/html/rfc4791) - CalDAV specification  
- [Bullet Journal Method](https://bulletjournal.com/pages/learn) - Original bullet journal methodology

### Support and Development
- GitHub Repository: [daytimeforninja/mindgoblin](https://github.com/daytimeforninja/mindgoblin)
- Issue Tracking: GitHub Issues
- License: AGPL-3.0-or-later