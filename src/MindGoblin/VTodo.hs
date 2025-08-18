{-# LANGUAGE OverloadedStrings #-}

module MindGoblin.VTodo
  ( taskToVTodo
  , taskToIcs
  , escapeText
  , foldLine
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day, formatTime, defaultTimeLocale)
import Text.Printf (printf)

import MindGoblin.Types

-- | Convert a task to appropriate iCalendar format (VTODO or VEVENT)
-- @user-story: Users want events to appear in calendar, tasks in todo list
taskToIcs :: Task -> Text
taskToIcs task = case taskBullet task of
  Event -> taskToVEvent task
  _ -> taskToVTodo task

-- | Convert an event task to VEVENT format
-- @user-story: Events (o bullet) appear as calendar appointments
taskToVEvent :: Task -> Text
taskToVEvent task = T.unlines $ filter (not . T.null) $
  [ "BEGIN:VCALENDAR"
  , "VERSION:2.0"
  , "PRODID:-//Mind Goblin//mg//EN"
  , "BEGIN:VEVENT"
  , "UID:" <> formatUID (taskUid task)
  , foldLine $ "SUMMARY:" <> escapeText (taskText task)
  , formatEventDateTime "DTSTART" (taskDate task) (taskEventTime task)
  , formatEventEndTime "DTEND" (taskDate task) (taskEventTime task)
  , categoriesLine (taskContexts task)
  , descriptionLine (taskNotes task)
  , "END:VEVENT"
  , "END:VCALENDAR"
  ]
  where
    categoriesLine [] = ""
    categoriesLine contexts = "CATEGORIES:" <> T.intercalate "," (map contextToText contexts)
    
    contextToText (Context t) = escapeText t
    
    descriptionLine [] = ""
    descriptionLine notes = "DESCRIPTION:" <> escapeText (T.intercalate "\n" notes)
    
    formatUID Nothing = "unknown"
    formatUID (Just uid) = uid
    
    -- Format date/time for VEVENT
    formatEventDateTime :: Text -> Day -> Maybe Text -> Text
    formatEventDateTime field date Nothing = 
      -- No time specified, use all-day event
      field <> ":" <> T.pack (formatTime defaultTimeLocale "%Y%m%d" date)
    formatEventDateTime field date (Just timeStr) = 
      -- Parse time and create proper DTSTART/DTEND
      let baseDate = T.pack $ formatTime defaultTimeLocale "%Y%m%d" date
          startTime = case parseTimeRange timeStr of
                        Just (start, _) -> start  -- Use start time from range
                        Nothing -> timeStr         -- Use the whole string
          isoTime = parseTimeToISO startTime
      in field <> ":" <> baseDate <> "T" <> isoTime
    
    -- Parse time range like "2-4pm" or "14:00-16:00"
    parseTimeRange :: Text -> Maybe (Text, Text)
    parseTimeRange t
      | "-" `T.isInfixOf` t = 
          case T.splitOn "-" t of
            [start, end] ->
              -- For "2-4pm", start is "2" and end is "4pm"
              -- We need to add "pm" to start too
              let suffix = T.takeWhileEnd (`elem` ("ampmAMPM" :: String)) end
                  startWithSuffix = if T.null suffix || any (`T.isSuffixOf` start) ["am", "pm", "AM", "PM"]
                                    then start
                                    else start <> suffix
              in Just (startWithSuffix, end)
            _ -> Nothing
      | otherwise = Nothing
    
    -- Parse "2pm" or "14:00" to ISO format "140000"
    parseTimeToISO :: Text -> Text
    parseTimeToISO t
      | "pm" `T.isSuffixOf` T.toLower t = 
          let hourStr = T.dropEnd 2 t
              hour = case reads (T.unpack hourStr) :: [(Int, String)] of
                       [(h, "")] -> if h < 12 then h + 12 else h
                       _ -> 14  -- Default to 2pm
          in T.pack $ printf "%02d0000" hour
      | "am" `T.isSuffixOf` T.toLower t = 
          let hourStr = T.dropEnd 2 t
              hour = case reads (T.unpack hourStr) :: [(Int, String)] of
                       [(h, "")] -> if h == 12 then 0 else h
                       _ -> 9  -- Default to 9am
          in T.pack $ printf "%02d0000" hour
      | ":" `T.isInfixOf` t =
          let parts = T.splitOn ":" t
          in case parts of
               [h, m] -> T.pack (printf "%02d%02d00" 
                                  (read (T.unpack h) :: Int) 
                                  (read (T.unpack m) :: Int))
               _ -> "140000"  -- Default
      | otherwise = "140000"  -- Default to 2pm
    
    -- Format end time (from range or 1 hour after start)
    formatEventEndTime :: Text -> Day -> Maybe Text -> Text
    formatEventEndTime field date Nothing = 
      -- No time specified, use all-day event
      field <> ":" <> T.pack (formatTime defaultTimeLocale "%Y%m%d" date)
    formatEventEndTime field date (Just timeStr) = 
      let baseDate = T.pack $ formatTime defaultTimeLocale "%Y%m%d" date
      in case parseTimeRange timeStr of
        Just (_, endTimeStr) ->
          -- Use the end time from the range
          field <> ":" <> baseDate <> "T" <> parseTimeToISO endTimeStr
        Nothing ->
          -- Add 1 hour to start time for end time
          let startTimeISO = parseTimeToISO timeStr
              hourStr = T.take 2 startTimeISO
              hour = case reads (T.unpack hourStr) :: [(Int, String)] of
                       [(h, "")] -> if h < 23 then h + 1 else 0
                       _ -> 15
              endTimeISO = T.pack $ printf "%02d0000" hour
          in field <> ":" <> baseDate <> "T" <> endTimeISO

-- | Convert a task to VTODO format
-- @test-spec: TEST_SPEC.md#2.2-vtodo-content
-- @implements: README.md#task-to-vtodo-mapping
-- @user-story: Users' tasks sync to calendar apps as VTODO entries
-- @data-flow: Task -> VTODO fields -> RFC5545 format -> .ics content
taskToVTodo :: Task -> Text
taskToVTodo task = T.unlines $ filter (not . T.null) $
  [ "BEGIN:VCALENDAR"
  , "VERSION:2.0"
  , "PRODID:-//Mind Goblin//mg//EN"
  , "BEGIN:VTODO"
  , "UID:" <> formatUID (taskUid task)
  , foldLine $ "SUMMARY:" <> escapeText (taskText task)
  , "STATUS:" <> bulletToStatus (taskBullet task)
  , priorityLine (taskBullet task)
  , categoriesLine (taskContexts task)
  , dueLine (taskDue task)
  , descriptionLine (taskNotes task)
  , "END:VTODO"
  , "END:VCALENDAR"
  ]
  where
    priorityLine Priority = "PRIORITY:1"
    priorityLine _ = ""
    
    categoriesLine [] = ""
    categoriesLine contexts = "CATEGORIES:" <> T.intercalate "," (map contextToText contexts)
    
    contextToText (Context t) = escapeText t
    
    dueLine Nothing = ""
    dueLine (Just date) = "DUE:" <> formatDate date
    
    descriptionLine [] = ""
    descriptionLine notes = "DESCRIPTION:" <> escapeText (T.intercalate "\n" notes)
    
    formatUID Nothing = "unknown"
    formatUID (Just uid) = uid
    
    formatDate date = T.pack $ formatTime defaultTimeLocale "%Y%m%d" date

-- | Convert bullet type to VTODO status
-- @test-spec: TEST_SPEC.md#2.2-vtodo-content
-- @implements: README.md#task-to-vtodo-mapping
bulletToStatus :: Bullet -> Text
bulletToStatus Open = "NEEDS-ACTION"
bulletToStatus Priority = "NEEDS-ACTION"
bulletToStatus Completed = "COMPLETED"
bulletToStatus _ = "NEEDS-ACTION"

-- | Escape special characters per RFC5545
-- @test-spec: TEST_SPEC.md#2.2-vtodo-content
-- @implements: README.md#task-to-vtodo-mapping
-- @user-story: Special characters are properly escaped for iCalendar
-- @data-flow: Raw text -> character escaping -> iCalendar-safe text
escapeText :: Text -> Text
escapeText = T.replace "," "\\," 
           . T.replace ";" "\\;"
           . T.replace "\n" "\\n"
           . T.replace "\\" "\\\\"

-- | Fold long lines at 75 characters per RFC5545
-- @test-spec: TEST_SPEC.md#2.2-vtodo-content
-- @implements: README.md#task-to-vtodo-mapping
-- @user-story: Long lines are folded to meet iCalendar specification
-- @data-flow: Long line -> split at 75 chars -> continuation lines with space
foldLine :: Text -> Text
foldLine text
  | T.length text <= 75 = text
  | otherwise = 
      let (first, rest) = T.splitAt 75 text
      in first <> "\n " <> foldLine rest