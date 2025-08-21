{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Options.Applicative
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.FilePath ((</>))
import System.Directory (getHomeDirectory, doesFileExist, createDirectoryIfMissing)
import System.Exit (exitFailure)
import Control.Monad (when, unless)
import Data.List (partition)
import Data.Time (getCurrentTime, Day, getCurrentTimeZone, utcToLocalTime, localDay)

import MindGoblin.Types
import MindGoblin.Parser
import MindGoblin.FileOps
import MindGoblin.VDirSyncer

-- | CLI commands
data Command
  = Sync SyncOptions
  | Push PushOptions  
  | Pull PullOptions
  | Init InitOptions
  | Watch WatchOptions
  | Stats StatsOptions
  | List ListOptions
  deriving (Show)

-- | Sync command options
data SyncOptions = SyncOptions
  { syncDryRun :: Bool
  , syncNoVdirsyncer :: Bool
  , syncFile :: Maybe FilePath
  } deriving (Show)

-- | Push command options
data PushOptions = PushOptions
  { pushDryRun :: Bool
  , pushFile :: Maybe FilePath
  } deriving (Show)

-- | Pull command options
data PullOptions = PullOptions
  { pullDryRun :: Bool
  , pullFile :: Maybe FilePath
  } deriving (Show)

-- | Init command options
data InitOptions = InitOptions
  { initForce :: Bool
  } deriving (Show)

-- | Watch command options
data WatchOptions = WatchOptions
  { watchFile :: Maybe FilePath
  } deriving (Show)

-- | Stats command options
data StatsOptions = StatsOptions
  { statsFile :: Maybe FilePath
  } deriving (Show)

-- | List command options
data ListOptions = ListOptions
  { listFile :: Maybe FilePath
  , listAll :: Bool
  , listCompleted :: Bool
  , listContext :: Maybe Text
  } deriving (Show)

-- | Parse command line arguments
parseCommand :: Parser Command
parseCommand = subparser $ mconcat
  [ command "sync" (info (Sync <$> parseSyncOptions) (progDesc "Generate vdir, run vdirsyncer, update completions"))
  , command "push" (info (Push <$> parsePushOptions) (progDesc "Only update vdir from todo.txt"))
  , command "pull" (info (Pull <$> parsePullOptions) (progDesc "Only check vdir for completions"))
  , command "init" (info (Init <$> parseInitOptions) (progDesc "Initialize config and vdirsyncer"))
  , command "watch" (info (Watch <$> parseWatchOptions) (progDesc "Auto-sync on file changes"))
  , command "stats" (info (Stats <$> parseStatsOptions) (progDesc "Show task statistics"))
  , command "list" (info (List <$> parseListOptions) (progDesc "List tasks organized by priority"))
  ]

-- | Parse sync options
parseSyncOptions :: Parser SyncOptions
parseSyncOptions = SyncOptions
  <$> switch (long "dry-run" <> help "Show what would be synced")
  <*> switch (long "no-vdirsyncer" <> help "Skip vdirsyncer, only update vdir")
  <*> optional (strOption (long "file" <> metavar "FILE" <> help "Use custom todo.txt file"))

-- | Parse push options
parsePushOptions :: Parser PushOptions
parsePushOptions = PushOptions
  <$> switch (long "dry-run" <> help "Show what would be pushed")
  <*> optional (strOption (long "file" <> metavar "FILE" <> help "Use custom todo.txt file"))

-- | Parse pull options
parsePullOptions :: Parser PullOptions
parsePullOptions = PullOptions
  <$> switch (long "dry-run" <> help "Show what would be pulled")
  <*> optional (strOption (long "file" <> metavar "FILE" <> help "Use custom todo.txt file"))

-- | Parse init options
parseInitOptions :: Parser InitOptions
parseInitOptions = InitOptions
  <$> switch (long "force" <> help "Overwrite existing config files")

-- | Parse watch options
parseWatchOptions :: Parser WatchOptions
parseWatchOptions = WatchOptions
  <$> optional (strOption (long "file" <> metavar "FILE" <> help "Use custom todo.txt file"))

-- | Parse stats options
parseStatsOptions :: Parser StatsOptions
parseStatsOptions = StatsOptions
  <$> optional (strOption (long "file" <> metavar "FILE" <> help "Use custom todo.txt file"))

-- | Parse list options
parseListOptions :: Parser ListOptions
parseListOptions = ListOptions
  <$> optional (strOption (long "file" <> metavar "FILE" <> help "Use custom todo.txt file"))
  <*> switch (long "all" <> help "Show all tasks, not just today's")
  <*> switch (long "completed" <> help "Include completed tasks")
  <*> optional (strOption (long "context" <> metavar "CONTEXT" <> help "Filter by context (e.g., @work)"))

-- | Program options
opts :: ParserInfo Command
opts = info (parseCommand <**> helper <**> versionOption)
  ( fullDesc
  <> progDesc "Mind Goblin - Bullet journal todo.txt to CalDAV sync"
  <> header "mg - bullet journal CalDAV sync via vdirsyncer"
  )
  where
    versionOption = infoOption "mg 1.2.0.0"
      ( long "version"
      <> short 'v'
      <> help "Show version information" )

-- | Main entry point
main :: IO ()
main = do
  cmd <- execParser opts
  runCommand cmd

-- | Get current local date (not UTC)
getCurrentLocalDate :: IO Day
getCurrentLocalDate = do
  utc <- getCurrentTime
  tz <- getCurrentTimeZone
  let local = utcToLocalTime tz utc
  return $ localDay local

-- | Execute the given command
runCommand :: Command -> IO ()
runCommand (Sync options) = runSync options
runCommand (Push options) = runPush options
runCommand (Pull options) = runPull options
runCommand (Init options) = runInit options
runCommand (Watch options) = runWatch options
runCommand (Stats options) = runStats options
runCommand (List options) = runList options

-- | Run sync command
-- @implements: README.md#mg-sync
-- @user-story: Users run mg sync to push tasks and pull completions
-- @data-flow: todo.txt -> vdir -> vdirsyncer -> CalDAV -> completion status -> todo.txt
runSync :: SyncOptions -> IO ()
runSync options = do
  putStrLn "🧠 Mind Goblin - Syncing tasks..."
  
  todoFile <- getTodoFile (syncFile options)
  vdirPath <- getVdirPath
  
  when (syncDryRun options) $ putStrLn "🔍 Dry run mode - no changes will be made"
  
  -- Step 1: Parse todo.txt
  content <- TIO.readFile todoFile
  case parseTodoFile content of
    Left err -> do
      putStrLn $ "❌ Failed to parse todo.txt: " ++ show err
      exitFailure
    Right sections -> do
      today <- getCurrentLocalDate
      let allTasks = concatMap sectionEntries sections
      let syncableTasks = filter (shouldSyncTask today) allTasks
      putStrLn $ "📝 Found " ++ show (length allTasks) ++ " total entries"
      putStrLn $ "🔄 Syncing " ++ show (length syncableTasks) ++ " actionable items (today only)"
      
      unless (syncDryRun options) $ do
        -- Step 2: Write tasks and events to appropriate directories
        calendarPath <- getCalendarPath
        let (events, tasks) = partition (\t -> taskBullet t == Event) syncableTasks
        
        unless (null tasks) $ do
          putStrLn $ "📤 Writing " ++ show (length tasks) ++ " tasks to vdir..."
          cleanVdirForTasks vdirPath tasks  -- Remove old task files first
          mapM_ (writeTaskToVdir vdirPath) tasks
        
        unless (null events) $ do
          putStrLn $ "📅 Writing " ++ show (length events) ++ " events to calendar..."
          createDirectoryIfMissing True calendarPath
          cleanVdirForTasks calendarPath events  -- Remove old event files first
          mapM_ (writeTaskToVdir calendarPath) events
        
        -- Step 3: Run vdirsyncer for both pairs (unless disabled)
        unless (syncNoVdirsyncer options) $ do
          putStrLn "🔄 Running vdirsyncer..."
          unless (null tasks) $ runVdirsyncer "sync tasks"
          unless (null events) $ runVdirsyncer "sync calendar"
        
        -- Step 4: Check for completed tasks and events
        putStrLn "📥 Checking for completed tasks..."
        vdirTasks <- readVdirTasks vdirPath
        calendarEvents <- readVdirTasks calendarPath
        let allItems = vdirTasks ++ calendarEvents
        let completedTasks = filter isTaskCompleted allItems
        
        -- Step 5: Update todo.txt with completions
        -- Only update tasks that aren't already completed in the local file
        let localTasks = concatMap sectionEntries sections
        let localCompletedTexts = [taskText t | t <- localTasks, taskBullet t == Completed]
        let tasksToUpdate = filter (\t -> taskText t `notElem` localCompletedTexts) completedTasks
        
        unless (null tasksToUpdate) $ do
          putStrLn $ "📋 Found " ++ show (length tasksToUpdate) ++ " tasks to mark as completed:"
          mapM_ (\task -> putStrLn $ "  - " ++ T.unpack (taskText task)) tasksToUpdate
        
        when (length completedTasks > length tasksToUpdate) $ do
          putStrLn $ "⏭️  Skipped " ++ show (length completedTasks - length tasksToUpdate) ++ " already completed tasks"
        
        mapM_ (markTaskCompleted todoFile) tasksToUpdate
        
        putStrLn $ "✅ Sync complete! Marked " ++ show (length tasksToUpdate) ++ " tasks as completed"

-- | Run push command
-- @implements: README.md#mg-push
-- @user-story: Users run mg push to only send tasks to CalDAV without pulling
-- @data-flow: todo.txt -> vdir -> CalDAV (no completion check)
runPush :: PushOptions -> IO ()
runPush options = do
  putStrLn "🧠 Mind Goblin - Pushing tasks..."
  
  todoFile <- getTodoFile (pushFile options)
  vdirPath <- getVdirPath
  
  when (pushDryRun options) $ putStrLn "🔍 Dry run mode - no changes will be made"
  
  content <- TIO.readFile todoFile
  case parseTodoFile content of
    Left err -> do
      putStrLn $ "❌ Failed to parse todo.txt: " ++ show err
      exitFailure
    Right sections -> do
      today <- getCurrentLocalDate
      let allTasks = concatMap sectionEntries sections
      let syncableTasks = filter (shouldSyncTask today) allTasks
      putStrLn $ "📝 Found " ++ show (length allTasks) ++ " total entries"
      putStrLn $ "🔄 Pushing " ++ show (length syncableTasks) ++ " actionable items (today only)"
      
      unless (pushDryRun options) $ do
        -- Separate events from tasks
        calendarPath <- getCalendarPath
        let (events, tasks) = partition (\t -> taskBullet t == Event) syncableTasks
        
        unless (null tasks) $ do
          putStrLn $ "📤 Writing " ++ show (length tasks) ++ " tasks to vdir..."
          cleanVdirForTasks vdirPath tasks  -- Remove old task files first
          mapM_ (writeTaskToVdir vdirPath) tasks
        
        unless (null events) $ do
          putStrLn $ "📅 Writing " ++ show (length events) ++ " events to calendar..."
          createDirectoryIfMissing True calendarPath
          cleanVdirForTasks calendarPath events  -- Remove old event files first
          mapM_ (writeTaskToVdir calendarPath) events
        
        putStrLn "✅ Push complete!"

-- | Run pull command
-- @implements: README.md#mg-pull
-- @user-story: Users run mg pull to only check for completed tasks
-- @data-flow: CalDAV -> vdir -> todo.txt completion updates
runPull :: PullOptions -> IO ()
runPull options = do
  putStrLn "🧠 Mind Goblin - Pulling completions..."
  
  todoFile <- getTodoFile (pullFile options)
  vdirPath <- getVdirPath
  
  when (pullDryRun options) $ putStrLn "🔍 Dry run mode - no changes will be made"
  
  -- First run vdirsyncer to get latest from CalDAV
  putStrLn "🔄 Running vdirsyncer..."
  runVdirsyncer "sync tasks"
  runVdirsyncer "sync calendar"
  
  -- Check for completed tasks and events
  putStrLn "📥 Checking for completed tasks..."
  vdirTasks <- readVdirTasks vdirPath
  
  calendarPath <- getCalendarPath
  calendarEvents <- readVdirTasks calendarPath
  
  let allItems = vdirTasks ++ calendarEvents
  let completedTasks = filter isTaskCompleted allItems
  
  unless (pullDryRun options) $ do
    -- Update todo.txt with completions
    mapM_ (markTaskCompleted todoFile) completedTasks
  
  putStrLn $ "✅ Pull complete! " ++ 
    (if pullDryRun options 
     then "Would mark " ++ show (length completedTasks) ++ " tasks as completed"
     else "Marked " ++ show (length completedTasks) ++ " tasks as completed")

-- | Run init command
-- @implements: README.md#mg-init
-- @user-story: Users run mg init to set up configuration
-- @data-flow: Create config directories and template files
runInit :: InitOptions -> IO ()
runInit options = do
  putStrLn "🧠 Mind Goblin - Initializing configuration..."
  
  configDir <- getConfigDir
  createDirectoryIfMissing True configDir
  
  let configFile = configDir </> "config"
  
  -- Check if config exists
  configExists <- doesFileExist configFile
  
  when (configExists && not (initForce options)) $ do
    putStrLn $ "❌ Config file already exists: " ++ configFile
    putStrLn "Use --force to overwrite"
    exitFailure
  
  -- Create mg config
  TIO.writeFile configFile defaultConfig
  putStrLn $ "✅ Created mg config: " ++ configFile
  
  putStrLn ""
  putStrLn "🎉 Initialization complete!"
  putStrLn ""
  putStrLn "Mind Goblin will use your existing vdirsyncer 'tasks' pair."
  putStrLn "Make sure you have vdirsyncer configured with a 'tasks' pair that syncs to ~/.local/share/mg/tasks/"
  putStrLn ""
  putStrLn "Next steps:"
  putStrLn "1. Run: vdirsyncer sync tasks  # Test your tasks sync"
  putStrLn "2. Run: mg sync               # Start using Mind Goblin"

-- | Run watch command
-- @implements: README.md#mg-watch
-- @user-story: Users run mg watch to auto-sync on file changes
-- @data-flow: File watch -> detect changes -> auto-sync
runWatch :: WatchOptions -> IO ()
runWatch _options = do
  putStrLn "🧠 Mind Goblin - Watch mode (not implemented yet)"
  putStrLn "⚠️  File watching not implemented in this version"
  putStrLn "💡 Use a cron job or run 'mg sync' manually for now"

-- | Run stats command
-- @implements: README.md#mg-stats
-- @user-story: Users run mg stats to see task statistics
-- @data-flow: todo.txt -> parse -> count tasks by status
runStats :: StatsOptions -> IO ()
runStats options = do
  putStrLn "🧠 Mind Goblin - Task Statistics"
  
  todoFile <- getTodoFile (statsFile options)
  content <- TIO.readFile todoFile
  
  case parseTodoFile content of
    Left err -> do
      putStrLn $ "❌ Failed to parse todo.txt: " ++ show err
      exitFailure
    Right sections -> do
      let allTasks = concatMap sectionEntries sections
      let openTasks = filter (\t -> taskBullet t == Open) allTasks
      let completedTasks = filter (\t -> taskBullet t == Completed) allTasks
      let priorityTasks = filter (\t -> taskBullet t == Priority) allTasks
      let shoppingTasks = filter (\t -> taskBullet t == Shopping) allTasks
      let events = filter (\t -> taskBullet t == Event) allTasks
      let ideas = filter (\t -> taskBullet t == Idea) allTasks
      today <- getCurrentLocalDate
      let syncable = filter (shouldSyncTask today) allTasks
      
      putStrLn ""
      putStrLn $ "📊 Total entries: " ++ show (length allTasks)
      putStrLn $ ". Open tasks: " ++ show (length openTasks)
      putStrLn $ "x Completed: " ++ show (length completedTasks)
      putStrLn $ "! Priority: " ++ show (length priorityTasks)
      putStrLn $ "$ Shopping: " ++ show (length shoppingTasks)
      putStrLn $ "o Events: " ++ show (length events)
      putStrLn $ "* Ideas: " ++ show (length ideas)
      putStrLn $ "🔄 Syncable: " ++ show (length syncable)
      putStrLn ""
      
      let completionRate :: Double
          completionRate = if length allTasks > 0
            then fromIntegral (length completedTasks) / fromIntegral (length allTasks) * 100
            else 0
      putStrLn $ "✅ Completion rate: " ++ show (round completionRate :: Int) ++ "%"

-- | Run list command
-- @implements: README.md#mg-list
-- @user-story: Users run mg list to see today's tasks organized by priority
-- @data-flow: todo.txt -> parse -> filter by date/context -> sort by priority -> display
runList :: ListOptions -> IO ()
runList options = do
  putStrLn "🧠 Mind Goblin - Task List"
  
  todoFile <- getTodoFile (listFile options)
  content <- TIO.readFile todoFile
  
  case parseTodoFile content of
    Left err -> do
      putStrLn $ "❌ Failed to parse todo.txt: " ++ show err
      exitFailure
    Right sections -> do
      today <- getCurrentLocalDate
      let allTasks = concatMap sectionEntries sections
      
      -- Apply filters
      let filteredTasks = filter (filterTask today options) allTasks
      
      -- Group by priority
      let priorityTasks = filter (\t -> taskBullet t == Priority) filteredTasks
      let openTasks = filter (\t -> taskBullet t == Open) filteredTasks
      let shoppingTasks = filter (\t -> taskBullet t == Shopping) filteredTasks
      let eventTasks = filter (\t -> taskBullet t == Event) filteredTasks
      let completedTasks = filter (\t -> taskBullet t == Completed) filteredTasks
      
      putStrLn ""
      
      -- Display tasks by priority
      unless (null priorityTasks) $ do
        putStrLn "🔥 Priority Tasks:"
        mapM_ (putStrLn . formatTask) priorityTasks
        putStrLn ""
      
      unless (null openTasks) $ do
        putStrLn "📋 Open Tasks:"
        mapM_ (putStrLn . formatTask) openTasks
        putStrLn ""
      
      unless (null shoppingTasks) $ do
        putStrLn "🛒 Shopping:"
        mapM_ (putStrLn . formatTask) shoppingTasks
        putStrLn ""
      
      unless (null eventTasks) $ do
        putStrLn "📅 Events:"
        mapM_ (putStrLn . formatTask) eventTasks
        putStrLn ""
      
      when (listCompleted options && not (null completedTasks)) $ do
        putStrLn "✅ Completed:"
        mapM_ (putStrLn . formatTask) completedTasks
        putStrLn ""
      
      let totalShown = length filteredTasks
      putStrLn $ "📊 Showing " ++ show totalShown ++ " tasks" ++
        (if listAll options then "" else " (today only)")

-- | Filter tasks based on list options
filterTask :: Day -> ListOptions -> Task -> Bool
filterTask today options task = 
  dateFilter && contextFilter && completionFilter
  where
    dateFilter = listAll options || taskDate task == today
    contextFilter = case listContext options of
      Nothing -> True
      Just ctx -> Context ctx `elem` taskContexts task
    completionFilter = listCompleted options || taskBullet task /= Completed

-- | Format a task for display
formatTask :: Task -> String
formatTask task = 
  bulletChar ++ " " ++ T.unpack (taskText task) ++ contextStr ++ dueStr
  where
    bulletChar = case taskBullet task of
      Open -> "."
      Completed -> "x"
      Priority -> "!"
      Event -> "o"
      Idea -> "*"
      Shopping -> "$"
      _ -> "?"
    contextStr = if null (taskContexts task)
                then ""
                else " " ++ unwords (map (\(Context c) -> "@" ++ T.unpack c) (taskContexts task))
    dueStr = case taskDue task of
      Nothing -> ""
      Just due -> " Due: " ++ show due

-- | Get todo.txt file path
getTodoFile :: Maybe FilePath -> IO FilePath
getTodoFile (Just file) = return file
getTodoFile Nothing = do
  home <- getHomeDirectory
  return $ home </> "todo.txt"

-- | Get config directory path
getConfigDir :: IO FilePath
getConfigDir = do
  home <- getHomeDirectory
  return $ home </> ".config" </> "mg"

-- | Get vdir path for tasks (XDG data directory)
getVdirPath :: IO FilePath
getVdirPath = do
  home <- getHomeDirectory
  return $ home </> ".local" </> "share" </> "mg" </> "tasks"

-- | Get calendar path for events
getCalendarPath :: IO FilePath
getCalendarPath = do
  home <- getHomeDirectory
  return $ home </> ".cache" </> "calendars" </> "default"

-- | Default mg configuration
defaultConfig :: Text
defaultConfig = T.unlines
  [ "[sync]"
  , "auto_sync = true"
  , "sync_interval = 300  # seconds"
  , "backup_on_sync = true"
  , ""
  , "[paths]"
  , "todo_file = \"~/todo.txt\""
  , "vdir_path = \"~/.local/share/mg/tasks\"  # XDG data directory"
  ]

