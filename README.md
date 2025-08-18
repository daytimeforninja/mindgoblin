# Mind Goblin

A comprehensive bullet journal task synchronization system implementing bidirectional CalDAV integration through vdirsyncer middleware.

## Overview

Mind Goblin (`mg`) is a command-line task management solution designed to maintain synchronization between plain text bullet journal files and CalDAV-compatible calendar services. The system provides complete bidirectional synchronization, ensuring that task state changes in either the local text file or remote calendar applications are propagated to all connected endpoints.

The application implements a robust parsing engine for bullet journal notation, supporting the full spectrum of bullet journal methodologies while maintaining strict compatibility with industry-standard CalDAV protocols. All synchronization operations are performed through the vdirsyncer framework, ensuring reliable communication with diverse calendar service providers including Google Calendar, iCloud, FastMail, and self-hosted solutions.

## Installation

Mind Goblin is distributed through the Nix package manager, providing reproducible builds and dependency management across all supported platforms.

### Evaluation Installation
For initial testing and evaluation purposes:
```bash
nix run github:daytimeforninja/mindgoblin -- init
nix run github:daytimeforninja/mindgoblin -- sync
```

### Production Installation
For permanent system integration:
```bash
nix profile install github:daytimeforninja/mindgoblin
mg init && mg sync
```

The installation process will automatically configure all required dependencies including the vdirsyncer synchronization engine and establish the necessary directory structures for optimal operation.

## Core Features

### Bullet Journal Notation System
Mind Goblin implements a comprehensive bullet journal notation parser supporting the following standardized symbols:
- `.` - Open tasks requiring action
- `x` - Completed tasks 
- `!` - High-priority urgent tasks
- `o` - Events and appointments
- `<` - Scheduled tasks with specific timing
- `>` - Migrated tasks moved to different time periods
- `-` - Notes and reference information
- `*` - Ideas and future considerations

### Bidirectional Synchronization
The system maintains real-time bidirectional synchronization between local text files and remote CalDAV endpoints. Task state modifications in either location are automatically detected and propagated to all synchronized endpoints within the next sync cycle.

### CalDAV Protocol Compliance
Full compliance with RFC 5545 (iCalendar) and RFC 4791 (CalDAV) specifications, ensuring compatibility with industry-standard calendar services and self-hosted solutions.

### Vdirsyncer Integration
Native integration with vdirsyncer provides robust, tested synchronization capabilities with comprehensive error handling and conflict resolution.

## File Format Specification

### Structure
Mind Goblin operates on plaintext files following a date-sectioned format with bullet journal notation:

```
2025-08-17
. Buy groceries @errands
! Call dentist @urgent Due: 2025-08-18
x Finished project @work
- Meeting notes: discussed Q4 plans
```

### Date Sections
Files are organized by date headers in ISO 8601 format (YYYY-MM-DD). Each date section contains all tasks and entries for that specific day.

### Context Tags
Tasks may include context tags using the `@context` notation, enabling categorization and filtering capabilities. Multiple contexts per task are supported.

### Due Dates
Tasks may specify due dates using the format `Due: YYYY-MM-DD`. Due date information is synchronized to the calendar application's due date field.

### Synchronization Behavior
When `mg sync` is executed, the system performs a complete bidirectional synchronization cycle with **today-only filtering**:

- **Calendar sync**: Only tasks from today's date are synchronized to your calendar application, keeping it focused and uncluttered
- **Historical record**: Your complete todo.txt file maintains the full historical record of all tasks across all dates
- **Bidirectional updates**: Tasks marked complete in calendar applications are detected and updated in the local text file
- **Task modifications**: Changes are propagated in both directions for today's tasks only

This approach ensures your calendar app shows only what's actionable today while preserving the complete bullet journal history in your text file.

## Command Reference

### Primary Commands

```bash
mg sync    # Execute complete bidirectional synchronization cycle
mg push    # Upload local tasks to calendar endpoints (unidirectional)
mg pull    # Download task state changes from calendar endpoints (unidirectional)
mg init    # Initialize configuration and establish vdirsyncer connection
mg stats   # Display comprehensive task statistics and metrics
mg watch   # Enable continuous file monitoring with automatic synchronization
```

### Command Details

#### `mg sync`
Performs a complete bidirectional synchronization cycle including:
1. Upload of new local tasks to calendar endpoints
2. Download of task state changes from calendar endpoints
3. Execution of vdirsyncer sync operations
4. Update of local file with remote changes
5. Conflict resolution and error handling

#### `mg init`
Establishes initial system configuration including:
- Creation of required directory structures
- vdirsyncer configuration validation
- Calendar endpoint discovery and authentication
- Initial synchronization state establishment

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