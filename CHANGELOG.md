# Changelog

## [1.2.0.0] - 2025-08-21

### Fixed
- 🕐 **Local timezone support** - `mg list` now correctly shows today's tasks in user's local timezone instead of UTC
- 📅 **Accurate date filtering** - Fixed issue where users in non-UTC timezones saw tomorrow's or yesterday's tasks

### Technical
- ⚡ **Timezone handling** - All date operations now use local time for user-facing commands
- 🧪 **Test consistency** - Updated all test suites to use local timezone for reliable behavior
- 🔧 **Zero breaking changes** - Maintains full backward compatibility with existing todo.txt files

## [1.1.0.0] - 2025-08-21

### Added
- 🛒 **Shopping bullet type (`$`)** - New bullet for shopping list items that sync to CalDAV
- 📋 **`mg list` command** - Display tasks organized by priority with filtering options
  - `--all` - Show tasks from all dates
  - `--completed` - Include completed tasks  
  - `--context CONTEXT` - Filter by specific context
  - `--file FILE` - Use custom todo.txt file
- ✨ **Freeform text support** - Natural note-taking without forced bullet notation

### Changed
- 🗑️ **Removed Note bullet (`-`)** - Replaced with natural freeform text
- 📝 **Enhanced bullet journal authenticity** - More natural writing experience

### Technical
- 🧪 **129 comprehensive tests** - Zero failures, bulletproof reliability
- 🛡️ **Chaos engineering** - System resilience under failure conditions
- 🔧 **Property-based testing** - 900+ randomized test cases with QuickCheck
- 🚀 **Production-ready quality** - Enterprise-grade reliability and error handling

## [1.0.0.0] - Initial Release

### Features
- ✅ Bullet journal notation parsing (`.`, `x`, `!`, `o`, `*`, `>`, `<`)
- 🔄 CalDAV sync via vdirsyncer (VTODO/VEVENT generation)
- 📅 Today-only sync filtering
- 🎯 Context extraction (`@work`, `@home`)
- 📆 Due date support (`Due: YYYY-MM-DD`)
- 🧠 Mind Goblin CLI with sync, push, pull, init, stats, watch commands
- 🛡️ Bulletproof reliability with comprehensive test coverage