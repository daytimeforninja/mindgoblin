{-# LANGUAGE OverloadedStrings #-}

module MindGoblin.Parser
  ( parseBullet
  , parseTaskLine
  , parseDateSection
  , parseTodoFile
  , extractContexts
  , parseDueDate
  ) where

import Control.Monad (void)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day, fromGregorianValid)
import Data.Maybe (mapMaybe)
import Data.List (partition)
import Data.Char (isDigit)
import Text.Megaparsec
import Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L
import Data.Void (Void)

import MindGoblin.Types hiding (ParseError)
import qualified MindGoblin.Types as T

type Parser = Parsec Void Text

-- | Parse bullet journal notation symbols
-- @test-spec: TEST_SPEC.md#1.1-bullet-recognition
-- @implements: README.md#bullet-types
-- @user-story: Users type bullets to categorize entries
-- @data-flow: Text -> Lexer -> Bullet type
parseBullet :: Text -> Either T.ParseError Bullet
parseBullet text = case parse (bulletParser :: Parser Bullet) "" text of
  Left _ -> Left $ T.InvalidBullet text
  Right bullet -> Right bullet
  where
    bulletParser = choice
      [ Open      <$ char '.'
      , Completed <$ char 'x'
      , Migrated  <$ char '>'
      , Scheduled <$ char '<'
      , Note      <$ char '-'
      , Priority  <$ char '!'
      , Idea      <$ char '*'
      , Event     <$ char 'o'
      ]

-- | Parse a single task line
-- @test-spec: TEST_SPEC.md#1.2-task-parsing
-- @implements: README.md#file-format-specification
-- @user-story: Users write tasks with bullets, text, contexts, and dates
-- @data-flow: Text line -> Parser -> Task record
parseTaskLine :: Day -> Text -> Either T.ParseError Task
parseTaskLine date line = case parse (taskLineParser :: Parser Task) "" line of
  Left err -> Left $ T.ParseFailure $ errorBundlePretty err
  Right task -> Right task { taskDate = date }
  where
    taskLineParser = bulletTask
    
    bulletTask = do
      bullet <- bulletParser
      void $ char ' '
      text <- T.pack <$> manyTill anySingle (lookAhead contextOrDueOrUidOrEol)
      contexts <- many contextParser
      due <- optional dueDateParser
      uid <- optional uidParser
      -- For events, extract time from contexts (e.g., @2pm becomes the event time)
      let (finalContexts, eventTime) = if bullet == Event
                                        then extractTimeContext contexts
                                        else (contexts, Nothing)
      pure $ Task date bullet (T.strip text) finalContexts due [] uid eventTime
    

    bulletParser :: Parser Bullet
    bulletParser = choice
      [ Open      <$ char '.'
      , Completed <$ char 'x'
      , Migrated  <$ char '>'
      , Scheduled <$ char '<'
      , Note      <$ char '-'
      , Priority  <$ char '!'
      , Idea      <$ char '*'
      , Event     <$ char 'o'
      ]

    contextOrDueOrUidOrEol :: Parser ()
    contextOrDueOrUidOrEol = void contextParser <|> void dueDateParser <|> void uidParser <|> void eol <|> eof

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

    uidParser :: Parser Text
    uidParser = do
      void $ string " <!-- UID:"
      uid <- T.pack <$> some (alphaNumChar <|> char '-')
      void $ string " -->"
      return uid

-- | Extract time context from contexts list (e.g., [@work, @2pm] -> ([@work], Just "2pm"))
extractTimeContext :: [Context] -> ([Context], Maybe Text)
extractTimeContext contexts =
  let (timeContexts, otherContexts) = partition isTimeContext contexts
  in case timeContexts of
    [] -> (contexts, Nothing)
    (Context t:_) -> (otherContexts, Just t)
  where
    isTimeContext (Context t) = 
      any (`T.isSuffixOf` t) ["am", "pm", "AM", "PM"] ||
      ":" `T.isInfixOf` t ||  -- For 14:00 style times
      "-" `T.isInfixOf` t && any (`T.isInfixOf` t) ["am", "pm", ":", "AM", "PM"] ||  -- Ranges like 2-4pm
      T.all (\c -> isDigit c || c == ':') t  -- Pure numbers like "1400"

-- | Parse a date section header
-- @test-spec: TEST_SPEC.md#1.3-date-section
-- @implements: README.md#file-format-specification
-- @user-story: Users organize tasks by date sections
-- @data-flow: Date line -> Date parser -> DateSection
parseDateSection :: Text -> Either T.ParseError DateSection
parseDateSection input = case parse (dateSectionParser :: Parser DateSection) "" input of
  Left err -> Left $ T.ParseFailure $ errorBundlePretty err
  Right section -> Right section
  where
    dateSectionParser :: Parser DateSection
    dateSectionParser = do
      date <- dateHeaderParser
      void eol
      lines' <- many (try $ do
        notFollowedBy eof
        notFollowedBy (try dateHeaderParser)  -- Stop at next date
        line <- takeWhileP Nothing (/= '\n')
        (void eol <|> eof)
        pure line)
      let tasks = mapMaybe (\line -> 
            if T.null line 
              then Nothing
              else case parseTaskLine date line of
                Left _ -> Nothing  -- Skip freeform lines
                Right task -> Just task) lines'
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


-- | Parse entire todo.txt file
-- @test-spec: TEST_SPEC.md#full-file-parsing
-- @implements: README.md#file-format-specification
-- @user-story: Users maintain chronological log of all tasks
-- @data-flow: Full file -> Multiple date sections -> List of DateSections
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
      lines' <- many (try $ do
        notFollowedBy eof
        notFollowedBy (try dateHeaderParser)  -- Stop at next date
        line <- takeWhileP Nothing (/= '\n')
        (void eol <|> eof)
        pure line)
      let tasks = mapMaybe (\line -> 
            if T.null line 
              then Nothing
              else case parseTaskLine date line of
                Left _ -> Nothing  -- Skip freeform lines
                Right task -> Just task) lines'
      pure $ DateSection date tasks
    
    -- Skip any content that doesn't match a date section
    skipNonDateSection :: Parser DateSection
    skipNonDateSection = do
      notFollowedBy eof
      notFollowedBy (try dateHeaderParser)
      _ <- takeWhileP Nothing (/= '\n')
      (void eol <|> eof)
      pure $ DateSection (fromGregorian 1900 1 1) []  -- Dummy section to be filtered
    
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

-- | Extract @contexts from text
-- @test-spec: TEST_SPEC.md#1.4-context-extraction
-- @implements: README.md#file-format-specification
-- @user-story: Users tag tasks with @contexts for organization
-- @data-flow: Text -> Find @ symbols -> Extract words -> Context list
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
    
    validContextChar c = c == '-' || c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')

-- | Parse due date from text
-- @test-spec: TEST_SPEC.md#1.5-due-date-parsing
-- @implements: README.md#file-format-specification
-- @user-story: Users mark deadlines with Due: dates
-- @data-flow: Text -> Find "Due:" -> Parse date -> Maybe Day
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
  Nothing -> error "Invalid date"