{-# LANGUAGE OverloadedStrings #-}

module MindGoblin.FileOps (
    markTaskCompleted,
    writeTaskToVdir,
    readVdirTasks,
    isTaskCompleted,
    cleanVdirForTasks,
) where

import Control.DeepSeq (force)
import Control.Exception (IOException, evaluate, try)
import Control.Monad (forM_, when)
import Crypto.Hash (Digest, SHA256, hash)
import Data.ByteString qualified as BS
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.Time (Day, fromGregorianValid, getCurrentTime, utctDay)
import System.Directory (doesFileExist, listDirectory, removeFile)
import System.FilePath ((</>))
import Text.Read (readMaybe)

import MindGoblin.Types
import MindGoblin.VTodo

{- | Mark a task as completed in todo.txt file
@test-spec: TEST_SPEC.md#4.1-in-place-update
@implements: README.md#task-completion-sync
@user-story: Tasks completed in calendar apps are marked x in todo.txt
@data-flow: Completed task -> find line in file -> change bullet -> direct write
-}
markTaskCompleted :: FilePath -> Task -> IO (Either Text ())
markTaskCompleted todoFile task = do
    -- Check if file exists first
    fileExists <- doesFileExist todoFile
    if not fileExists
        then return $ Left $ T.pack $ "Todo file does not exist: " ++ todoFile
        else do
            -- Read current content with completely strict I/O
            result <- try $ do
                bytes <- BS.readFile todoFile -- Strict ByteString read
                let fileContent = TE.decodeUtf8 bytes -- Decode to Text
                _ <- evaluate (force fileContent) -- Force full evaluation
                return fileContent

            case result of
                Left (e :: IOException) ->
                    return $ Left $ T.pack $ "Failed to read todo file: " ++ show e
                Right content -> do
                    let lines' = T.lines content

                    -- Find and update the task line
                    let updatedLines = map (updateTaskLine task) lines'
                    let newContent = T.unlines updatedLines
                    _ <- evaluate (force newContent) -- Force evaluation

                    -- Direct write - no temp files
                    writeResult <- try $ TIO.writeFile todoFile newContent

                    case writeResult of
                        Left (e :: IOException) ->
                            return $ Left $ T.pack $ "Failed to update todo file: " ++ show e
                        Right _ -> return $ Right ()

-- | Update a single line if it matches the task
updateTaskLine :: Task -> Text -> Text
updateTaskLine task line
    | isMatchingTask task line = updateBulletToCompleted line
    | otherwise = line

-- | Check if a line matches the given task using content-based matching
isMatchingTask :: Task -> Text -> Bool
isMatchingTask task line =
    -- Match by task text and contexts (more reliable than UIDs)
    let hasTaskText = taskText task `T.isInfixOf` line
        hasAllContexts = all (\(Context ctx) -> ("@" <> ctx) `T.isInfixOf` line) (taskContexts task)
     in hasTaskText && hasAllContexts

-- | Update bullet to completed (clean, no UIDs)
updateBulletToCompleted :: Text -> Text
updateBulletToCompleted line =
    -- Simply change bullet to completed, keep everything else as-is
    case T.uncons line of
        Just ('.', rest) -> "x" <> rest
        Just ('!', rest) -> "x" <> rest -- Priority tasks also become completed
        Just ('o', rest) -> "x" <> rest -- Events also become completed
        Just ('<', rest) -> "x" <> rest -- Scheduled tasks also become completed
        _ -> line

{- | Generate deterministic ID based on task content
This prevents duplicate .ics files for the same task
-}
generateDeterministicUID :: Task -> Text
generateDeterministicUID task =
    let content = taskText task <> T.concat (map (\(Context c) -> "@" <> c) (taskContexts task))
        contentBytes = TE.encodeUtf8 content
        digest = hash contentBytes :: Digest SHA256
        hashStr = show digest
     in T.pack $ take 16 hashStr -- First 16 chars of SHA256 hash

{- | Write a task to vdir as .ics file, using deterministic UID
@test-spec: TEST_SPEC.md#3.3-vdir-writing
@implements: README.md#task-to-ics-conversion
@user-story: Tasks in todo.txt appear as calendar entries (no duplicates)
@data-flow: Task -> deterministic UID -> write to vdir/UID.ics
-}
writeTaskToVdir :: FilePath -> Task -> IO ()
writeTaskToVdir vdirPath task = do
    -- Use deterministic UID based on task content to prevent duplicates
    let uidText = generateDeterministicUID task
    let taskWithUid = task{taskUid = Just uidText}
    let filename = T.unpack uidText ++ ".ics"
    let filepath = vdirPath </> filename
    let icsContent = taskToIcs taskWithUid
    TIO.writeFile filepath icsContent

{- | Read all tasks from vdir .ics files
@test-spec: TEST_SPEC.md#3.1-vdir-reading
@implements: README.md#ics-to-task-conversion
@user-story: Calendar changes are detected and synced back
@data-flow: vdir/*.ics -> parse VTODO -> extract task data
-}
readVdirTasks :: FilePath -> IO [Task]
readVdirTasks vdirPath = do
    files <- listDirectory vdirPath
    let icsFiles = filter (T.isSuffixOf ".ics" . T.pack) files
    results <- mapM (readTaskFromIcs vdirPath) icsFiles
    -- Filter out parse failures and extract successful tasks
    return $ mapMaybe eitherToMaybe results
  where
    eitherToMaybe (Right task) = Just task
    eitherToMaybe (Left _) = Nothing

-- | Read a single task from an .ics file
readTaskFromIcs :: FilePath -> FilePath -> IO (Either Text Task)
readTaskFromIcs vdirPath filename = do
    let filepath = vdirPath </> filename
    content <- TIO.readFile filepath
    currentDay <- utctDay <$> getCurrentTime
    return $ parseVTodoFromIcs currentDay content

{- | Parse iCalendar content from .ics file to Task
@test-spec: TEST_SPEC.md#3.1-vdir-reading
@implements: README.md#ics-parsing
@user-story: Calendar files are converted back to tasks
@data-flow: .ics content -> VTODO/VEVENT parser -> Task record
-}
parseVTodoFromIcs :: Day -> Text -> Either Text Task
parseVTodoFromIcs defaultDate content =
    -- Validate basic iCalendar structure first
    let lines' = T.lines content
        hasBeginCalendar = any ("BEGIN:VCALENDAR" `T.isInfixOf`) lines'
        hasEndCalendar = any ("END:VCALENDAR" `T.isInfixOf`) lines'
        hasBeginTodo = any ("BEGIN:VTODO" `T.isInfixOf`) lines'
        hasBeginEvent = any ("BEGIN:VEVENT" `T.isInfixOf`) lines'
     in if not hasBeginCalendar || not hasEndCalendar || (not hasBeginTodo && not hasBeginEvent)
            then Left "Invalid iCalendar format: missing required BEGIN/END tags"
            else
                let isVEvent = hasBeginEvent
                    summaryLine = findField "SUMMARY:" lines'
                    statusLine = findField "STATUS:" lines'
                    uidLine = findField "UID:" lines'
                    categoriesLine = findField "CATEGORIES:" lines'
                    dueLine = findField "DUE:" lines'

                    summary = maybe "Unknown task" (T.drop 8) summaryLine -- Remove "SUMMARY:"
                    isCompleted = maybe False ("COMPLETED" `T.isInfixOf`) statusLine
                    -- If it's a VEVENT, treat as Event bullet, otherwise check completion status
                    bullet
                        | isVEvent = Event
                        | isCompleted = Completed
                        | otherwise = Open
                    uid = fmap (T.drop 4) uidLine -- Remove "UID:" and keep as Text
                    contexts = maybe [] parseCategories categoriesLine
                    due = dueLine >>= parseDueDateFromIcs
                 in Right $
                        Task
                            { taskDate = defaultDate -- Use current date instead of hardcoded
                            , taskBullet = bullet
                            , taskText = summary
                            , taskContexts = contexts
                            , taskDue = due
                            , taskNotes = []
                            , taskUid = uid
                            , taskEventTime = Nothing -- TODO: Parse from DTSTART if VEVENT
                            }

-- | Find a field in VTODO lines
findField :: Text -> [Text] -> Maybe Text
findField prefix lines' =
    let matching = filter (T.isPrefixOf prefix) lines'
     in case matching of
            (line : _) -> Just line
            [] -> Nothing

-- | Parse categories from CATEGORIES line
parseCategories :: Text -> [Context]
parseCategories line =
    let categoriesText = T.drop 11 line -- Remove "CATEGORIES:"
        categoryList = T.splitOn "," categoriesText
     in map (Context . T.strip) categoryList

-- | Parse due date from DUE line
parseDueDateFromIcs :: Text -> Maybe Day
parseDueDateFromIcs line =
    let dateText = T.drop 4 line -- Remove "DUE:"
        dateStr = T.unpack $ T.strip dateText
     in if length dateStr == 8
            then do
                year <- readMaybe (take 4 dateStr)
                month <- readMaybe (take 2 (drop 4 dateStr))
                day <- readMaybe (drop 6 dateStr)
                fromGregorianValid year month day
            else Nothing

{- | Check if a task is completed
@test-spec: TEST_SPEC.md#3.2-completion-detection
@implements: README.md#completion-status-detection
@user-story: Completed tasks are detected from calendar apps
@data-flow: Task -> check bullet -> completed status
-}
isTaskCompleted :: Task -> Bool
isTaskCompleted task = taskBullet task == Completed

{- | Clean vdir directory to only contain files for the given tasks
@implements: today-only sync - removes old task files
@user-story: "Old tasks should be removed from CalDAV when using today-only sync"
@data-flow: vdir/*.ics -> check if corresponds to current tasks -> remove if not
-}
cleanVdirForTasks :: FilePath -> [Task] -> IO ()
cleanVdirForTasks vdirPath tasks = do
    -- Get all current .ics files
    files <- listDirectory vdirPath
    let icsFiles = filter (T.isSuffixOf ".ics" . T.pack) files

    -- Get UIDs of tasks we want to keep
    let keepUIDs = map generateDeterministicUID tasks

    -- Remove files that don't correspond to current tasks
    forM_ icsFiles $ \filename -> do
        let uid = T.pack $ take (length filename - 4) filename -- Remove .ics extension
        let filepath = vdirPath </> filename
        fileExists <- doesFileExist filepath
        when (fileExists && uid `notElem` keepUIDs) $ do
            removeFile filepath
