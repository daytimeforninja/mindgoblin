{-# LANGUAGE OverloadedStrings #-}

module MindGoblin.Parser (
    parseBullet,
    parseTaskLine,
    parseDateSection,
    parseTodoFile,
    extractContexts,
    parseDueDate,
    parseZettelTag,
    parseZettelWithContinuation,
    parseDateSectionWithZettels,
) where

import Control.Monad (void)
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.List (partition)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (Day, fromGregorianValid)
import Data.Void (Void)
import Text.Megaparsec
import Text.Megaparsec.Char
import Text.Megaparsec.Char.Lexer qualified as L

import MindGoblin.Types hiding (ParseError)
import MindGoblin.Types qualified as T

type Parser = Parsec Void Text

-- | Shared bullet parser for reuse
bulletParser :: Parser Bullet
bulletParser =
    choice
        [ Open <$ char '.'
        , Completed <$ char 'x'
        , Migrated <$ char '>'
        , Scheduled <$ char '<'
        , Priority <$ char '!'
        , Idea <$ char '*'
        , Event <$ char 'o'
        , Shopping <$ char '$'
        ]

{- | Parse bullet journal notation symbols
@test-spec: TEST_SPEC.md#1.1-bullet-recognition
@implements: README.md#bullet-types
@user-story: Users type bullets to categorize entries
@data-flow: Text -> Lexer -> Bullet type
-}
parseBullet :: Text -> Either T.ParseError Bullet
parseBullet text = case parse (bulletParser :: Parser Bullet) "" text of
    Left _ -> Left $ T.InvalidBullet text
    Right bullet -> Right bullet

{- | Parse a single task line
@test-spec: TEST_SPEC.md#1.2-task-parsing
@implements: README.md#file-format-specification
@user-story: Users write tasks with bullets, text, contexts, and dates
@data-flow: Text line -> Parser -> Task record
-}
parseTaskLine :: Day -> Text -> Either T.ParseError Task
parseTaskLine date line = case parse (taskLineParser :: Parser Task) "" line of
    Left err -> Left $ T.ParseFailure $ errorBundlePretty err
    Right task -> Right task{taskDate = date}
  where
    taskLineParser = bulletTask

    bulletTask = do
        bullet <- bulletParser
        void $ char ' '
        text <- T.pack <$> manyTill anySingle (lookAhead contextOrDueOrEol)
        contexts <- many contextParser
        due <- optional dueDateParser
        -- For events, extract time from contexts (e.g., @2pm becomes the event time)
        let (finalContexts, eventTime) =
                if bullet == Event
                    then extractTimeContext contexts
                    else (contexts, Nothing)
        pure $ Task date bullet (T.strip text) finalContexts due [] Nothing eventTime

    contextOrDueOrEol :: Parser ()
    contextOrDueOrEol = void contextParser <|> void dueDateParser <|> void eol <|> eof

    contextParser :: Parser Context
    contextParser = do
        void $ char '@'
        context <- T.pack <$> some (alphaNumChar <|> char '-' <|> char '_' <|> char ':')
        _ <- optional (char ' ')
        pure $ Context context

    dueDateParser :: Parser Day
    dueDateParser = do
        void $ string "Due: "
        year <- L.decimal
        void $ char '-'
        month <- L.decimal
        void $ char '-'
        day <- L.decimal
        _ <- optional timeParser -- ignore time if present
        _ <- optional (char ' ')
        case fromGregorianValid year month day of
            Just d -> pure d
            Nothing -> fail "Invalid date"

    timeParser :: Parser ()
    timeParser = do
        void $ char ' '
        void (L.decimal :: Parser Integer)
        void $ char ':'
        void (L.decimal :: Parser Integer)

-- | Extract time context from contexts list (e.g., [@work, @2pm] -> ([@work], Just "2pm"))
extractTimeContext :: [Context] -> ([Context], Maybe Text)
extractTimeContext contexts =
    let (timeContexts, otherContexts) = partition isTimeContext contexts
     in case timeContexts of
            [] -> (contexts, Nothing)
            (Context t : _) -> (otherContexts, Just t)
  where
    isTimeContext (Context t) =
        any (`T.isSuffixOf` t) ["am", "pm", "AM", "PM"]
            || ":" `T.isInfixOf` t
            || "-" `T.isInfixOf` t && any (`T.isInfixOf` t) ["am", "pm", ":", "AM", "PM"] -- For 14:00 style times
            || T.all (\c -> isDigit c || c == ':') t -- Ranges like 2-4pm
            -- Pure numbers like "1400"

{- | Parse a date section header
@test-spec: TEST_SPEC.md#1.3-date-section
@implements: README.md#file-format-specification
@user-story: Users organize tasks by date sections
@data-flow: Date line -> Date parser -> DateSection
-}
parseDateSection :: Text -> Either T.ParseError DateSection
parseDateSection input = case parse (dateSectionParser :: Parser DateSection) "" input of
    Left err -> Left $ T.ParseFailure $ errorBundlePretty err
    Right section -> Right section
  where
    dateSectionParser :: Parser DateSection
    dateSectionParser = do
        date <- dateHeaderParser
        void eol
        lines' <-
            many
                ( try $ do
                    notFollowedBy eof
                    notFollowedBy (try dateHeaderParser) -- Stop at next date
                    line <- takeWhileP Nothing (/= '\n')
                    (void eol <|> eof)
                    pure line
                )
        let tasks =
                mapMaybe
                    ( \line ->
                        if T.null line
                            then Nothing
                            else case parseTaskLine date line of
                                Left _ -> Nothing -- Skip freeform lines
                                Right task -> Just task
                    )
                    lines'
        pure $ DateSection date tasks

    dateHeaderParser :: Parser Day
    dateHeaderParser = do
        year <- L.decimal
        void $ char '-'
        month <- L.decimal
        void $ char '-'
        day <- L.decimal
        case fromGregorianValid year month day of
            Just d -> pure d
            Nothing -> fail "Invalid date"

{- | Parse entire todo.txt file
@test-spec: TEST_SPEC.md#full-file-parsing
@implements: README.md#file-format-specification
@user-story: Users maintain chronological log of all tasks
@data-flow: Full file -> Multiple date sections -> List of DateSections
-}
parseTodoFile :: Text -> Either T.ParseError [DateSection]
parseTodoFile input = case parse (todoFileParser :: Parser [DateSection]) "" input of
    Left err -> Left $ T.ParseFailure $ errorBundlePretty err
    Right sections -> Right sections
  where
    todoFileParser :: Parser [DateSection]
    todoFileParser = do
        sections <- many (try singleDateSectionParser <|> skipNonDateSection)
        eof
        pure $ filter (not . isEmptySection) sections

    singleDateSectionParser :: Parser DateSection
    singleDateSectionParser = do
        date <- dateHeaderParser
        void eol
        lines' <-
            many
                ( try $ do
                    notFollowedBy eof
                    notFollowedBy (try dateHeaderParser) -- Stop at next date
                    line <- takeWhileP Nothing (/= '\n')
                    (void eol <|> eof)
                    pure line
                )
        let tasks =
                mapMaybe
                    ( \line ->
                        if T.null line
                            then Nothing
                            else case parseTaskLine date line of
                                Left _ -> Nothing -- Skip freeform lines
                                Right task -> Just task
                    )
                    lines'
        pure $ DateSection date tasks

    -- Skip any content that doesn't match a date section
    skipNonDateSection :: Parser DateSection
    skipNonDateSection = do
        notFollowedBy eof
        notFollowedBy (try dateHeaderParser)
        _ <- takeWhileP Nothing (/= '\n')
        (void eol <|> eof)
        pure $ DateSection (fromGregorian 1900 1 1) [] -- Dummy section to be filtered
    isEmptySection :: DateSection -> Bool
    isEmptySection (DateSection date []) = date == fromGregorian 1900 1 1
    isEmptySection _ = False

    dateHeaderParser :: Parser Day
    dateHeaderParser = do
        year <- L.decimal
        void $ char '-'
        month <- L.decimal
        void $ char '-'
        day <- L.decimal
        case fromGregorianValid year month day of
            Just d -> pure d
            Nothing -> fail "Invalid date"

{- | Extract @contexts from text
@test-spec: TEST_SPEC.md#1.4-context-extraction
@implements: README.md#file-format-specification
@user-story: Users tag tasks with @contexts for organization
@data-flow: Text -> Find @ symbols -> Extract words -> Context list
-}
extractContexts :: Text -> [Context]
extractContexts text = mapMaybe extractContext (T.words text)
  where
    extractContext word
        | T.take 1 word == "@" && T.length word > 1 =
            let context = T.drop 1 word
             in if T.all validContextChar context
                    then Just $ Context context
                    else Nothing
        | otherwise = Nothing

    validContextChar c = c == '-' || c == '_' || isAsciiLower c || isAsciiUpper c || isDigit c

{- | Parse due date from text
@test-spec: TEST_SPEC.md#1.5-due-date-parsing
@implements: README.md#file-format-specification
@user-story: Users mark deadlines with Due: dates
@data-flow: Text -> Find "Due:" -> Parse date -> Maybe Day
-}
parseDueDate :: Text -> Maybe Day
parseDueDate text = case parse dueDateParser "" text of
    Left _ -> Nothing
    Right date -> date
  where
    dueDateParser :: Parser (Maybe Day)
    dueDateParser = do
        void $ string "Due: "
        year <- L.decimal
        void $ char '-'
        month <- L.decimal
        void $ char '-'
        day <- L.decimal
        _ <- optional timeParser -- ignore time if present
        pure $ fromGregorianValid year month day

    timeParser :: Parser ()
    timeParser = do
        void $ char ' '
        void (L.decimal :: Parser Integer)
        void $ char ':'
        void (L.decimal :: Parser Integer)

-- Helper function for date creation (used in tests)
fromGregorian :: Integer -> Int -> Int -> Day
fromGregorian y m d = case fromGregorianValid y m d of
    Just date -> date
    Nothing -> case fromGregorianValid 2025 1 1 of
        Just defaultDate -> defaultDate
        Nothing -> error "Internal error: default date invalid"

{- | Parse zettelkasten tag from text line  
@test-spec: ZETTLE.md#parsing
@implements: ZETTLE.md#syntax-design
@user-story: Users capture zettel seeds with #zettel:slug tags
@data-flow: Text line -> Zettel tag parser -> Zettel record
-}
parseZettelTag :: Text -> Either T.ParseError Zettel
parseZettelTag text = case parse zettelParser "" text of
    Left err -> Left $ T.ParseFailure $ errorBundlePretty err
    Right zettel -> Right zettel
  where
    zettelParser :: Parser Zettel
    zettelParser = do
        zettelType <- choice
            [ ZettelFull <$ string "#zettel:"
            , ZettelShort <$ string "#z:"  
            , ZettelIdea <$ string "#idea:"
            ]
        -- Parse everything after : until end of line
        rest <- takeWhileP Nothing (/= '\n')
        
        -- Find the first space and split slug/content
        case T.findIndex (== ' ') rest of
            Nothing -> fail "Missing content after slug"
            Just spaceIdx -> do
                let slug = T.take spaceIdx rest
                let content = T.drop (spaceIdx + 1) rest
                
                -- Validate slug format
                if T.length slug > 50
                    then fail "Slug too long (max 50 characters)"
                    else if not (T.all validSlugChar slug) || T.null slug
                        then fail "Invalid characters in slug (letters, numbers, hyphens only)"
                        else pure $ Zettel slug (T.strip content) [] [] zettelType
      where
        validSlugChar c = isAsciiLower c || isAsciiUpper c || isDigit c || c == '-'

{- | Parse zettel with continuation lines
@test-spec: ZETTLE.md#parsing  
@implements: ZETTLE.md#syntax-design
@user-story: Users add indented details under zettel tags
@data-flow: Main line + indented lines -> Zettel with continuation
-}
parseZettelWithContinuation :: Text -> Either T.ParseError Zettel
parseZettelWithContinuation text = case parse zettelWithContinuationParser "" text of
    Left err -> Left $ T.ParseFailure $ errorBundlePretty err
    Right zettel -> Right zettel
  where
    zettelWithContinuationParser :: Parser Zettel
    zettelWithContinuationParser = do
        -- Parse the main zettel line
        zettelType <- choice
            [ ZettelFull <$ string "#zettel:"
            , ZettelShort <$ string "#z:"  
            , ZettelIdea <$ string "#idea:"
            ]
        slug <- slugParser
        void $ char ' '
        content <- takeWhileP Nothing (/= '\n')
        void $ optional eol
        
        -- Parse continuation lines (indented)
        continuationLines <- many $ try $ do
            void $ string "  " -- Two spaces for indentation
            line <- takeWhileP Nothing (/= '\n')
            void $ optional eol
            pure $ T.strip line
        
        pure $ Zettel slug (T.strip content) continuationLines [] zettelType
    
    slugParser :: Parser Text
    slugParser = do
        slug <- T.pack <$> some validSlugChar
        if T.length slug > 50
            then fail "Slug too long (max 50 characters)"
            else pure slug
      where
        validSlugChar = alphaNumChar <|> char '-'

{- | Parse date section extracting both tasks and zettels
@test-spec: ZETTLE.md#integration
@implements: ZETTLE.md#unified-workflow
@user-story: Users mix tasks and zettel captures in daily sections
@data-flow: Date section -> extract tasks and zettels separately
-}
parseDateSectionWithZettels :: Text -> Either T.ParseError (DateSection, [Zettel])
parseDateSectionWithZettels input = case parse dateSectionWithZettelsParser "" input of
    Left err -> Left $ T.ParseFailure $ errorBundlePretty err
    Right result -> Right result
  where
    dateSectionWithZettelsParser :: Parser (DateSection, [Zettel])
    dateSectionWithZettelsParser = do
        date <- dateHeaderParser
        void eol
        lines' <-
            many
                ( try $ do
                    notFollowedBy eof
                    notFollowedBy (try dateHeaderParser) -- Stop at next date
                    line <- takeWhileP Nothing (/= '\n')
                    (void eol <|> eof)
                    pure line
                )
        
        -- Separate tasks from zettels
        let (tasks, zettels) = partitionLinesIntoTasksAndZettels date lines'
        
        pure (DateSection date tasks, zettels)
    
    partitionLinesIntoTasksAndZettels :: Day -> [Text] -> ([Task], [Zettel])
    partitionLinesIntoTasksAndZettels date lines' =
        let taskResults = mapMaybe (tryParseTask date) lines'
            zettelResults = mapMaybe tryParseZettel lines'
        in (taskResults, zettelResults)
    
    tryParseTask :: Day -> Text -> Maybe Task
    tryParseTask date line
        | T.null line = Nothing
        | otherwise = case parseTaskLine date line of
            Left _ -> Nothing
            Right task -> Just task
    
    tryParseZettel :: Text -> Maybe Zettel
    tryParseZettel line
        | T.null line = Nothing
        | T.isPrefixOf "#zettel:" line || T.isPrefixOf "#z:" line || T.isPrefixOf "#idea:" line =
            case parseZettelTag line of
                Left _ -> Nothing
                Right zettel -> Just zettel
        | otherwise = Nothing
    
    dateHeaderParser :: Parser Day
    dateHeaderParser = do
        year <- L.decimal
        void $ char '-'
        month <- L.decimal
        void $ char '-'
        day <- L.decimal
        case fromGregorianValid year month day of
            Just d -> pure d
            Nothing -> fail "Invalid date"
