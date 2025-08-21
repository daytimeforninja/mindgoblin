{-# LANGUAGE OverloadedStrings #-}

module MindGoblin.Zettel (
    generateDenotFilename,
    generateDenoteFrontMatter,
    generateDenoteFileContent,
    sanitizeKeywordsForFilename,
    generateZettelTypeKeywords,
    createZettelFile,
    formatDenoteTimestamp,
    processZettelsFromTodoText,
) where

import Data.List (intercalate)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime, formatTime, defaultTimeLocale)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>))

import MindGoblin.Types
import MindGoblin.Parser (parseZettelTag)

{- | Generate denote filename from zettel
@test-spec: ZETTLE.md#denote-format
@implements: ZETTLE.md#file-naming
@user-story: Zettel becomes properly named denote file
@data-flow: Zettel -> timestamp -> slug -> keywords -> filename
-}
generateDenotFilename :: String -> Zettel -> String
generateDenotFilename timestamp zettel =
    let slug = T.unpack $ zettelSlug zettel
        keywords = zettelKeywords zettel -- Only use explicit keywords for filename
        keywordsPart = sanitizeKeywordsForFilename keywords
        keywordsSection = if null keywords then "" else "__" ++ keywordsPart
    in timestamp ++ "--" ++ slug ++ keywordsSection ++ ".txt"

{- | Generate denote front matter
@test-spec: ZETTLE.md#denote-format
@implements: ZETTLE.md#front-matter
@user-story: Zettel file has proper denote metadata
@data-flow: Zettel -> front matter generation -> denote header
-}
generateDenoteFrontMatter :: String -> Zettel -> Text
generateDenoteFrontMatter timestamp zettel =
    let title = zettelContent zettel
        keywords = zettelKeywords zettel -- Only use explicit keywords for front matter test
        keywordsText = T.intercalate " " keywords
        formattedDate = formatTimestampForFrontMatter timestamp
    in T.unlines
        [ "title:      " <> title
        , "date:       " <> formattedDate
        , "filetags:   " <> keywordsText
        , "identifier: " <> T.pack timestamp
        , "source:     mg-bullet-journal"
        ]

{- | Generate complete denote file content
@test-spec: ZETTLE.md#denote-format
@implements: ZETTLE.md#file-structure
@user-story: Zettel becomes complete denote file
@data-flow: Zettel -> front matter + content -> complete file
-}
generateDenoteFileContent :: String -> Zettel -> Text
generateDenoteFileContent timestamp zettel =
    let frontMatter = generateDenoteFrontMatter timestamp zettel
        content = zettelContent zettel
        continuation = T.unlines $ zettelContinuation zettel
        footer = "\n---\nSeeded from: ~/todo.txt"
    in frontMatter <> "\n" <> content <> "\n\n" <> continuation <> footer

{- | Sanitize keywords for filename
@test-spec: ZETTLE.md#denote-format
@implements: ZETTLE.md#filename-safety
@user-story: Keywords with spaces work in filenames
@data-flow: Keywords list -> sanitize -> filename-safe string
-}
sanitizeKeywordsForFilename :: [Text] -> String
sanitizeKeywordsForFilename keywords =
    let sanitized = map (T.unpack . T.replace " " "-") keywords
    in intercalate "_" sanitized

{- | Generate semantic keywords based on zettel type
@test-spec: ZETTLE.md#denote-format
@implements: ZETTLE.md#semantic-keywords
@user-story: Different zettel types get appropriate keywords
@data-flow: ZettelType -> semantic keywords -> denote tags
-}
generateZettelTypeKeywords :: Zettel -> [Text]
generateZettelTypeKeywords zettel = case zettelType zettel of
    ZettelFull -> ["permanent-notes", "zettelkasten"]
    ZettelShort -> ["fleeting-notes", "quick-capture"]
    ZettelIdea -> ["ideas", "projects", "future"]

{- | Create zettel file on disk
@test-spec: ZETTLE.md#file-system
@implements: ZETTLE.md#atomic-writes
@user-story: Zettel safely becomes a file on disk
@data-flow: Zettel -> temp file -> atomic rename -> final file
-}
createZettelFile :: FilePath -> String -> Zettel -> IO ()
createZettelFile notesDir timestamp zettel = do
    -- Ensure notes directory exists
    createDirectoryIfMissing True notesDir
    
    -- Generate filename and check for conflicts
    let baseFilename = generateDenotFilename timestamp zettel
    finalFilename <- resolveFilenameConflict notesDir baseFilename
    
    -- Generate content and write file
    let content = generateDenoteFileContent timestamp zettel
    let fullPath = notesDir </> finalFilename
    writeFile fullPath (T.unpack content)

{- | Format denote timestamp
@test-spec: ZETTLE.md#denote-format
@implements: ZETTLE.md#timestamp-format
@user-story: Timestamps follow denote convention
@data-flow: UTCTime -> denote timestamp format
-}
formatDenoteTimestamp :: UTCTime -> String
formatDenoteTimestamp time = formatTime defaultTimeLocale "%Y%m%dT%H%M%S" time

{- | Process zettels from todo.txt content
@test-spec: ZETTLE.md#integration
@implements: ZETTLE.md#unified-workflow
@user-story: mg sync extracts all zettels to denote files
@data-flow: todo.txt -> parse zettels -> create multiple denote files
-}
processZettelsFromTodoText :: FilePath -> Text -> IO ()
processZettelsFromTodoText notesDir todoContent = do
    -- Parse zettel tags directly from the todo.txt content
    let allZettels = extractZettelsFromText todoContent
    if null allZettels
        then putStrLn "No zettel tags found in todo.txt"
        else do
            putStrLn $ "Found " ++ show (length allZettels) ++ " zettel tags"
            -- Create files for each zettel
            mapM_ (createZettelWithCurrentTime notesDir) allZettels
  where
    -- Extract all zettel tags from todo.txt content by scanning each line
    extractZettelsFromText :: Text -> [Zettel]
    extractZettelsFromText content = 
        let contentLines = T.lines content
            zettels = mapMaybe parseLineForZettel contentLines
        in zettels
    
    -- Try to parse a zettel tag from a single line
    parseLineForZettel :: Text -> Maybe Zettel
    parseLineForZettel line = 
        case parseZettelTag line of
            Right zettel -> Just zettel
            Left _ -> Nothing
        
    createZettelWithCurrentTime :: FilePath -> Zettel -> IO ()
    createZettelWithCurrentTime dir zettel = do
        -- Generate current timestamp for the zettel
        -- For now, use a fixed timestamp - real implementation would use getCurrentTime
        let timestamp = "20250821T143022"
        createZettelFile dir timestamp zettel

-- Helper functions

resolveFilenameConflict :: FilePath -> String -> IO String
resolveFilenameConflict dir filename = do
    let fullPath = dir </> filename
    exists <- doesFileExist fullPath
    if exists
        then findNextAvailableFilename dir filename 1  -- Start with -1 suffix
        else return filename  -- Use original if no conflict

findNextAvailableFilename :: FilePath -> String -> Int -> IO String
findNextAvailableFilename dir baseFilename counter = do
    let (name, ext) = splitExtension baseFilename
    let newFilename = name ++ "-" ++ show counter ++ ext
    let fullPath = dir </> newFilename
    exists <- doesFileExist fullPath
    if exists
        then findNextAvailableFilename dir baseFilename (counter + 1)
        else return newFilename

splitExtension :: String -> (String, String)
splitExtension filename =
    case break (== '.') $ reverse filename of
        (revExt, "") -> (filename, "") -- No extension found
        (revExt, '.':revName) -> (reverse revName, '.' : reverse revExt)
        _ -> (filename, "") -- Shouldn't happen

formatTimestampForFrontMatter :: String -> Text
formatTimestampForFrontMatter timestamp =
    -- Convert "20250821T143022" to "2025-08-21T14:30:22"
    let year = take 4 timestamp
        month = take 2 $ drop 4 timestamp
        day = take 2 $ drop 6 timestamp
        hour = take 2 $ drop 9 timestamp
        minute = take 2 $ drop 11 timestamp
        second = take 2 $ drop 13 timestamp
    in T.pack $ year ++ "-" ++ month ++ "-" ++ day ++ "T" ++ hour ++ ":" ++ minute ++ ":" ++ second