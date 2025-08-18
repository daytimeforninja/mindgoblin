# Mind Goblin Design Document

**Welcome to the Neighborhood of Code**

Hello, neighbor! Isn't it a beautiful day to learn about how things work? I'm so glad you want to understand Mind Goblin better. You know, understanding how things work helps us appreciate them even more.

## What We Believe In

Let me share with you the special ideas that make Mind Goblin who it is:

1. **One File**: All your tasks live in one cozy home called `~/todo.txt` - it's like a diary that never forgets
2. **Bullet Journal**: We use special symbols to mark different kinds of thoughts (just like using different crayons!)
3. **Minimal Sync**: We share tasks with your calendar, and only bring back what's been finished
4. **Historical Record**: Everything you've ever done stays written down, like a scrapbook of accomplishments
5. **Plain Text**: No fancy formats, just simple words that any program can read
6. **Leverage vdirsyncer**: We let our friend vdirsyncer do the hard work of talking to calendars

You see? Six simple ideas that work together, like good neighbors should.

## How We Write Things Down

### The Special Way We Organize

Let me show you how we write in our todo.txt file. It's very simple:

```
YYYY-MM-DD
<bullet> <task text> [<@context>...] [Due: YYYY-MM-DD]
<continuation lines indented with two spaces>
```

Isn't that nice and tidy?

### Our Special Symbols (Bullets)

Just like we have different feelings, we have different symbols for different kinds of tasks:

- `•` Open task (something that needs doing - like tying your shoes!)
- `×` Completed task (all done - doesn't that feel good?)
- `>` Migrated task (we'll do this another day)
- `<` Scheduled task (this has a special time, like dentist appointments)
- `−` Note (just something to remember, not something to do)
- `!` Priority task (this is really important!)
- `*` Idea (a wonderful thought for later)
- `○` Event (something happening, like a birthday party!)

🎵 *"Eight little symbols, sitting in a row,*
*Each one different, each one shows,*
*What kind of task we need to do,*
*Simple symbols, just for you!"* 🎵

### Let's Look at a Real Example

Here's what a day in your todo.txt might look like:

```
2025-08-16
• Review code changes @computer
× Submit expense report @computer
− Meeting notes: Discussed Q4 planning
! Fix production bug @urgent @computer Due: 2025-08-17
> Research new framework @computer
  Need to evaluate performance implications
  Check compatibility with existing stack

2025-08-17
• Follow up with client @calls
< Team standup 10am @meetings
* Consider switching to event sourcing
```

See how organized that looks? Each day has its own section, and each task has its own line. It's like a peaceful garden where everything has its place.

## How Everything Works Together

### Our Friend vdirsyncer

Let me tell you about how Mind Goblin works with its special friend vdirsyncer:

1. **Local vdir**: We keep calendar files in `~/.local/share/mg/tasks/` (like a mailbox for tasks!)
2. **vdirsyncer**: This friend knows how to talk to all different calendars (isn't that amazing?)
3. **mg**: Mind Goblin translates between your simple text and calendar language

It's like having a translator who helps two friends who speak different languages understand each other!

### Data Flow
```
~/todo.txt <--> mg <--> ~/.local/share/mg/tasks/ <--> vdirsyncer <--> CalDAV server
```

### vdir Structure
```
~/.local/share/mg/tasks/
├── 550e8400-e29b-41d4-a716-446655440000.ics
├── 6ba7b810-9dad-11d1-80b4-00c04fd430c8.ics
└── ...
```

## Configuration

### File Locations
```
~/.config/mg/
├── config              # mg configuration
└── vdirsyncer/         # vdirsyncer configuration (system location)
```

### mg Configuration (`~/.config/mg/config`)
```toml
[sync]
auto_sync = true
sync_interval = 300  # seconds
backup_on_sync = true

[paths]
todo_file = "~/todo.txt"
vdir_path = "~/.local/share/mg/tasks"  # XDG data directory
```

## Synchronization Behavior

### Task to VTODO Mapping

#### Fields Mapping
| todo.txt | VTODO Property | Notes |
|----------|---------------|-------|
| `•` bullet | STATUS:NEEDS-ACTION | Open task |
| `!` bullet | PRIORITY:1 | High priority |
| Task text | SUMMARY | Main description |
| Indented lines | DESCRIPTION | Additional notes |
| @context | CATEGORIES | Comma-separated |
| Due: date | DUE | RFC5545 date format |
| Content hash | UID | Deterministic based on task content |

#### Sync Process
1. **Parse**: Read todo.txt, extract tasks
2. **Generate**: Create/update .ics files in vdir using deterministic UIDs
3. **Sync**: Run `vdirsyncer sync tasks` 
4. **Check**: Read .ics files for STATUS:COMPLETED
5. **Update**: Change `•` to `×` in todo.txt

### How We Keep Track of Tasks

You know how every person is special and unique? Well, every task needs to be special and unique too! We give each task a special name (called a UID) based on what it says. This way, we never make two copies of the same task by accident.

And here's something wonderful: we don't write these special names in your todo.txt file. Your file stays clean and simple, just the way you wrote it. Isn't that thoughtful?

## Command Line Interface

### Commands
```bash
mg sync                  # Generate vdir, run vdirsyncer, update completions
mg push                  # Only update vdir from todo.txt
mg pull                  # Only check vdir for completions
mg watch                 # Auto-sync on file changes (not implemented)
mg stats                 # Show task statistics
mg init                  # Initialize config
```

### Options
```bash
--file PATH             # Use alternate file (default: ~/todo.txt)
--dry-run              # Show what would be synced
--no-vdirsyncer        # Skip vdirsyncer, only update vdir
```

### A Day in the Life with Mind Goblin

Let me show you how to use Mind Goblin every day:

```bash
# When you first start:
mg init                          # Wake up Mind Goblin!
vdirsyncer discover tasks        # Help it find your calendar
mg sync                         # Start sharing tasks

# Every day:
mg sync                         # Good morning! Let's see what's new
# ... write your tasks in todo.txt ...
mg sync                        # Good night! Let's save everything
```

🎵 *"Morning sync and evening sync,*
*Bookends to a peaceful day,*
*Write your tasks down in between,*
*Let the quiet come and stay!"* 🎵

## Dependencies

### Required
- vdirsyncer (configured with a 'tasks' pair)
- Haskell toolchain (GHC + Cabal)

### Haskell Libraries
- megaparsec (parsing)
- time (date handling)
- text (unicode text)
- iCalendar (RFC5545 support)
- process (vdirsyncer subprocess)
- cryptonite (deterministic UID generation)

## Dreams for Tomorrow

You know, I like to imagine all the wonderful things Mind Goblin might do someday:

- Multiple file support (one for work, one for home!)
- Task templates (for things you do often)
- Recurring tasks (like "water the plants every Tuesday")
- Archive old completed tasks (putting memories in a scrapbook)
- Natural language due dates ("next Tuesday" instead of dates)
- Git integration (keeping a history of all your changes)
- File watching (mg watch - always keeping an eye out for changes)

But you know what? Even if we never add these things, Mind Goblin is still special just the way it is.

### When Things Got Quiet

Let me tell you about my friend Margaret. Margaret was a teacher who loved making lists. Every morning, she would write down everything she needed to do on little index cards - one task per card. She'd carry them in her pocket all day.

But Margaret had a problem. She'd often lose cards, or forget to look at them, or worst of all - she'd lie awake at night trying to remember if she'd written something down or just thought about writing it down.

"My mind is so noisy," she told me one day. "All these tasks are shouting at me, even when I'm trying to sleep."

So we sat down together, and I showed her something simple. "What if," I said, "you wrote everything in one place? And what if that place could talk to your computer calendar, so you'd get reminders? And what if, when you finished something on your computer, it would mark itself done in your notebook?"

Margaret's eyes lit up. "That would be like... like having a quiet mind," she said.

And that's exactly what happened. She started using a simple text file. Every task she wrote down was one less thing making noise in her head. At night, she could look at her file and know - really know - that everything was captured. Nothing was forgotten.

"The quiet," she told me later, "the quiet is the best part. When everything is out of my head and written down, I can finally hear myself think. I can hear the birds. I can be present with my family."

That's what Mind Goblin does, neighbor. It helps you get all those noisy tasks out of your head and into a quiet, peaceful place where they wait patiently for you.

🎵 *"Out of your head and onto the page,*
*Tasks stop their shouting, end their rage,*
*Now your mind is clear and free,*
*Quiet as quiet can be!"* 🎵

---

Thank you for being my neighbor in this digital world. Remember: you're special just the way you are, and your tasks will be there when you need them. Won't you be my neighbor?