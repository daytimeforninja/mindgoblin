{-# LANGUAGE OverloadedStrings #-}

module MindGoblin.FileOps
  ( markTaskCompleted
  , writeTaskToVdir
  , readVdirTasks
  , isTaskCompleted
  , cleanVdirForTasks
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Control.Exception (evaluate, try, IOException)
import Control.DeepSeq (force)
import qualified Data.ByteString as BS
import qualified Data.Text.Encoding as TE
import Data.Time (Day, fromGregorianValid)
import Crypto.Hash (hash, Digest, SHA256)
import System.FilePath ((</>))
import System.Directory (listDirectory, removeFile, doesFileExist)
import Control.Monad (forM_, when)

import MindGoblin.Types
import MindGoblin.VTodo

-- | Mark a task as completed in todo.txt file
-- @test-spec: TEST_SPEC.md#4.1-in-place-update
-- @implements: README.md#task-completion-sync
-- @user-story: Tasks completed in calendar apps are marked x in todo.txt
-- @data-flow: Completed task -> find line in file -> change bullet -> direct write
markTaskCompleted :: FilePath -> Task -> IO ()
markTaskCompleted todoFile task = do
  -- Read current content with completely strict I/O
  content <- do
    bytes <- BS.readFile todoFile  -- Strict ByteString read
    let fileContent = TE.decodeUtf8 bytes  -- Decode to Text
    _ <- evaluate (force fileContent)  -- Force full evaluation
    return fileContent
  
  let lines' = T.lines content
  
  -- Find and update the task line
  let updatedLines = map (updateTaskLine task) lines'
  let newContent = T.unlines updatedLines
  _ <- evaluate (force newContent)  -- Force evaluation
  
  -- Direct write - no temp files
  result <- try $ TIO.writeFile todoFile newContent
  
  case result of
    Left (e :: IOException) -> 
      error $ "Failed to update todo file: " ++ show e
    Right _ -> return ()

-- | Update a single line if it matches the task
updateTaskLine :: Task -> Text -> Text
updateTaskLine task line
  | isMatchingTask task line = updateBulletAndUID task line
  | otherwise = line

-- | Check if a line matches the given task using content-based matching
isMatchingTask :: Task -> Text -> Bool
isMatchingTask task line =
  -- Match by task text and contexts (more reliable than UIDs)
  let hasTaskText = taskText task `T.isInfixOf` line
      hasAllContexts = all (\(Context ctx) -> ("@" <> ctx) `T.isInfixOf` line) (taskContexts task)
  in hasTaskText && hasAllContexts

-- | Update bullet to completed (clean, no UIDs)
updateBulletAndUID :: Task -> Text -> Text
updateBulletAndUID _task line =
  -- Simply change bullet to completed, keep everything else as-is
  case T.uncons line of
    Just ('.', rest) -> "x" <> rest
    Just ('!', rest) -> "x" <> rest  -- Priority tasks also become completed
    Just ('o', rest) -> "x" <> rest  -- Events also become completed
    Just ('<', rest) -> "x" <> rest  -- Scheduled tasks also become completed
    _ -> line

-- | Generate deterministic ID based on task content
-- This prevents duplicate .ics files for the same task
generateDeterministicUID :: Task -> Text
generateDeterministicUID task =
  let content = taskText task <> T.concat (map (\(Context c) -> "@" <> c) (taskContexts task))
      contentBytes = TE.encodeUtf8 content
      digest = hash contentBytes :: Digest SHA256
      hashStr = show digest
  in T.pack $ take 16 hashStr  -- First 16 chars of SHA256 hash

-- | Write a task to vdir as .ics file, using deterministic UID
-- @test-spec: TEST_SPEC.md#3.3-vdir-writing  
-- @implements: README.md#task-to-ics-conversion
-- @user-story: Tasks in todo.txt appear as calendar entries (no duplicates)
-- @data-flow: Task -> deterministic UID -> write to vdir/UID.ics
writeTaskToVdir :: FilePath -> Task -> IO ()
writeTaskToVdir vdirPath task = do
  -- Use deterministic UID based on task content to prevent duplicates
  let uidText = generateDeterministicUID task
  let taskWithUid = task { taskUid = Just uidText }
  let filename = T.unpack uidText ++ ".ics"
  let filepath = vdirPath </> filename
  let icsContent = taskToIcs taskWithUid
  TIO.writeFile filepath icsContent

-- | Read all tasks from vdir .ics files
-- @test-spec: TEST_SPEC.md#3.1-vdir-reading
-- @implements: README.md#ics-to-task-conversion
-- @user-story: Calendar changes are detected and synced back
-- @data-flow: vdir/*.ics -> parse VTODO -> extract task data
readVdirTasks :: FilePath -> IO [Task]
readVdirTasks vdirPath = do
  files <- listDirectory vdirPath
  let icsFiles = filter (T.isSuffixOf ".ics" . T.pack) files
  mapM (readTaskFromIcs vdirPath) icsFiles

-- | Read a single task from an .ics file
readTaskFromIcs :: FilePath -> FilePath -> IO Task
readTaskFromIcs vdirPath filename = do
  let filepath = vdirPath </> filename
  content <- TIO.readFile filepath
  case parseVTodoFromIcs content of
    Left err -> error $ "Failed to parse .ics file: " ++ T.unpack err
    Right task -> return task

-- | Parse iCalendar content from .ics file to Task
-- @test-spec: TEST_SPEC.md#3.1-vdir-reading
-- @implements: README.md#ics-parsing
-- @user-story: Calendar files are converted back to tasks
-- @data-flow: .ics content -> VTODO/VEVENT parser -> Task record
parseVTodoFromIcs :: Text -> Either Text Task
parseVTodoFromIcs content = 
  -- Simple parser for VTODO/VEVENT - in real implementation would be more robust
  let lines' = T.lines content
      isVEvent = any ("BEGIN:VEVENT" `T.isInfixOf`) lines'
      summaryLine = findField "SUMMARY:" lines'
      statusLine = findField "STATUS:" lines'
      uidLine = findField "UID:" lines'
      categoriesLine = findField "CATEGORIES:" lines'
      dueLine = findField "DUE:" lines'
      
      summary = maybe "Unknown task" (T.drop 8) summaryLine  -- Remove "SUMMARY:"
      isCompleted = maybe False ("COMPLETED" `T.isInfixOf`) statusLine
      -- If it's a VEVENT, treat as Event bullet, otherwise check completion status
      bullet = if isVEvent 
               then Event
               else if isCompleted then Completed else Open
      uid = fmap (T.drop 4) uidLine  -- Remove "UID:" and keep as Text
      contexts = maybe [] parseCategories categoriesLine
      due = dueLine >>= parseDueDateFromIcs
      
  in Right $ Task
       { taskDate = fromGregorian 2025 8 16  -- Default date - would parse from filename in real impl
       , taskBullet = bullet
       , taskText = summary
       , taskContexts = contexts
       , taskDue = due
       , taskNotes = []
       , taskUid = uid
       , taskEventTime = Nothing  -- TODO: Parse from DTSTART if VEVENT
       }

-- | Find a field in VTODO lines
findField :: Text -> [Text] -> Maybe Text
findField prefix lines' = 
  let matching = filter (T.isPrefixOf prefix) lines'
  in case matching of
    (line:_) -> Just line
    [] -> Nothing


-- | Parse categories from CATEGORIES line
parseCategories :: Text -> [Context]
parseCategories line =
  let categoriesText = T.drop 11 line  -- Remove "CATEGORIES:"
      categoryList = T.splitOn "," categoriesText
  in map (Context . T.strip) categoryList

-- | Parse due date from DUE line
parseDueDateFromIcs :: Text -> Maybe Day
parseDueDateFromIcs line =
  let dateText = T.drop 4 line  -- Remove "DUE:"
      dateStr = T.unpack $ T.strip dateText
  in if length dateStr == 8
     then let year = read (take 4 dateStr)
              month = read (take 2 (drop 4 dateStr))
              day = read (drop 6 dateStr)
          in fromGregorianValid year month day
     else Nothing

-- | Check if a task is completed
-- @test-spec: TEST_SPEC.md#3.2-completion-detection
-- @implements: README.md#completion-status-detection
-- @user-story: Completed tasks are detected from calendar apps
-- @data-flow: Task -> check bullet -> completed status
isTaskCompleted :: Task -> Bool
isTaskCompleted task = taskBullet task == Completed

-- | Clean vdir directory to only contain files for the given tasks
-- @implements: today-only sync - removes old task files
-- @user-story: "Old tasks should be removed from CalDAV when using today-only sync"
-- @data-flow: vdir/*.ics -> check if corresponds to current tasks -> remove if not
cleanVdirForTasks :: FilePath -> [Task] -> IO ()
cleanVdirForTasks vdirPath tasks = do
  -- Get all current .ics files
  files <- listDirectory vdirPath
  let icsFiles = filter (T.isSuffixOf ".ics" . T.pack) files
  
  -- Get UIDs of tasks we want to keep
  let keepUIDs = map generateDeterministicUID tasks
  
  -- Remove files that don't correspond to current tasks
  forM_ icsFiles $ \filename -> do
    let uid = T.pack $ take (length filename - 4) filename  -- Remove .ics extension
    let filepath = vdirPath </> filename
    fileExists <- doesFileExist filepath
    when (fileExists && uid `notElem` keepUIDs) $ do
      removeFile filepath

-- Helper function to convert Gregorian date
fromGregorian :: Integer -> Int -> Int -> Day
fromGregorian y m d = case fromGregorianValid y m d of
  Just date -> date
  Nothing -> error "Invalid date"