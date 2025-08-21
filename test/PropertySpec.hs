{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Main (main) where

import Data.Text qualified as T
import Data.Time (Day, fromGregorian, fromGregorianValid)
import Test.Hspec
import Test.QuickCheck

import MindGoblin.Parser
import MindGoblin.Types
import MindGoblin.VTodo

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "Property-Based Tests" $ do
        describe "Parser Properties" $ do
            it "bullet parsing roundtrip property" $ property $ \bullet ->
                let bulletChar = bulletToChar bullet
                    bulletText = T.singleton bulletChar
                 in parseBullet bulletText === Right bullet

            it "task text with contexts preserves context order" $ property $ \(contexts :: [Context]) ->
                let contextTexts = map (\i -> "context" <> T.pack (show i)) [1 .. length contexts `min` 3]
                    taskText = "Test task " <> T.intercalate " " (map ("@" <>) contextTexts)
                    contexts' = map Context contextTexts
                 in case parseTaskLine (fromGregorian 2025 8 16) (". " <> taskText) of
                        Right task -> taskContexts task `shouldBe` contexts'
                        Left _ -> expectationFailure "Failed to parse valid task"

            it "date parsing is stable" $
                forAll (choose (2020, 2030)) $ \year ->
                    forAll (choose (1, 12)) $ \month ->
                        forAll (choose (1, 28)) $ \day ->
                            -- Use 28 to avoid month-end issues
                            case fromGregorianValid year month day of
                                Just validDay ->
                                    let dateText =
                                            T.pack $
                                                show year
                                                    ++ "-"
                                                    ++ (if month < 10 then "0" else "")
                                                    ++ show month
                                                    ++ "-"
                                                    ++ (if day < 10 then "0" else "")
                                                    ++ show day
                                     in case parseDateSection (dateText <> "\n. Test task") of
                                            Right section -> sectionDate section `shouldBe` validDay
                                            Left _ -> expectationFailure "Failed to parse valid date"
                                Nothing -> return () -- Should not happen with our restricted range
        describe "VTodo Generation Properties" $ do
            it "escapeText is inverse of itself for safe characters" $ property $ \text ->
                let safeText = T.filter (\c -> c /= ',' && c /= ';' && c /= '\n' && c /= '\\') text
                 in T.length safeText > 0 ==>
                        let escaped = escapeText safeText
                         in -- For safe text, escaping should not change it
                            safeText `shouldBe` escaped

            it "line folding preserves content" $ property $ \text ->
                let folded = foldLine text
                    unfolded = T.replace "\n " "" folded
                 in T.length text > 0 ==> unfolded `shouldBe` text

            it "generated VTODO contains required fields" $ property $ \task ->
                let icsContent = taskToVTodo task
                    icsStr = T.unpack icsContent
                 in do
                        icsStr `shouldContain` "BEGIN:VCALENDAR"
                        icsStr `shouldContain` "END:VCALENDAR"
                        icsStr `shouldContain` "BEGIN:VTODO"
                        icsStr `shouldContain` "END:VTODO"
                        icsStr `shouldContain` "UID:"
                        icsStr `shouldContain` "STATUS:"

        describe "File Operations Properties" $ do
            it "task text and contexts are preserved in parsing" $ property $ \task ->
                let cleanText = T.strip (taskText task) -- Remove leading/trailing whitespace
                    taskLine = ". " <> cleanText <> " " <> T.intercalate " " (map (\(Context c) -> "@" <> c) (taskContexts task))
                 in T.length cleanText > 0 ==> -- Only test non-empty text
                        case parseTaskLine (taskDate task) taskLine of
                            Right parsedTask -> do
                                taskText parsedTask `shouldBe` cleanText
                                length (taskContexts parsedTask) `shouldBe` length (taskContexts task)
                            Left _ -> expectationFailure "Failed to parse valid task line"

        describe "Sync Logic Properties" $ do
            it "shouldSyncTask is consistent with date" $ property $ \task today ->
                let result1 = shouldSyncTask today task
                    result2 = shouldSyncTask today task
                 in result1 `shouldBe` result2

            it "only today's actionable tasks sync" $ property $ \task today ->
                let syncs = shouldSyncTask today task
                    isToday = taskDate task == today
                    isActionable = taskBullet task `elem` [Open, Completed, Priority, Scheduled, Event]
                 in syncs `shouldBe` (isToday && isActionable)

-- QuickCheck generators

-- Generate valid bullet characters
instance Arbitrary Bullet where
    arbitrary = elements [Open, Completed, Migrated, Scheduled, Priority, Idea, Event, Shopping]

-- Generate reasonable task text (avoiding problematic characters)
instance Arbitrary T.Text where
    arbitrary = T.pack <$> listOf1 (elements (['a' .. 'z'] ++ ['A' .. 'Z'] ++ ['0' .. '9'] ++ [' ', '-', '_']))

-- Generate valid contexts
instance Arbitrary Context where
    arbitrary = do
        contextName <- T.pack <$> listOf1 (elements (['a' .. 'z'] ++ ['0' .. '9']))
        return $ Context contextName

-- Generate reasonable tasks
instance Arbitrary Task where
    arbitrary = do
        date <- fromGregorian <$> choose (2020, 2030) <*> choose (1, 12) <*> choose (1, 28)
        bullet <- arbitrary
        text <- resize 50 arbitrary -- Limit text length
        contexts <- resize 3 arbitrary -- Limit context count
        due <- arbitrary
        notes <- resize 2 arbitrary -- Limit notes
        uid <- arbitrary
        eventTime <- arbitrary
        return $ Task date bullet text contexts due notes uid eventTime

instance Arbitrary Day where
    arbitrary = fromGregorian <$> choose (2020, 2030) <*> choose (1, 12) <*> choose (1, 28)

-- Helper functions
bulletToChar :: Bullet -> Char
bulletToChar Open = '.'
bulletToChar Completed = 'x'
bulletToChar Migrated = '>'
bulletToChar Scheduled = '<'
bulletToChar Priority = '!'
bulletToChar Idea = '*'
bulletToChar Event = 'o'
bulletToChar Shopping = '$'
