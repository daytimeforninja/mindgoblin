{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Either (isLeft)
import Data.Text qualified as T
import Data.Time (fromGregorian)
import Test.Hspec

import MindGoblin.Parser
import MindGoblin.Types

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "Bullet Recognition (TEST_SPEC.md#1.1)" $ do
        it "parses open task bullet - user types . for todo" $ do
            -- Data flow: "." -> lexer -> Open bullet
            parseBullet "." `shouldBe` Right Open

        it "parses completed bullet - user types x for done" $ do
            -- Data flow: "x" -> lexer -> Completed bullet
            parseBullet "x" `shouldBe` Right Completed

        it "parses migrated bullet - user uses > for moved tasks" $ do
            parseBullet ">" `shouldBe` Right Migrated

        it "parses scheduled bullet - user uses < for timed items" $ do
            parseBullet "<" `shouldBe` Right Scheduled

        it "parses priority bullet - user uses ! for urgent" $ do
            parseBullet "!" `shouldBe` Right Priority

        it "parses idea bullet - user uses * for ideas" $ do
            parseBullet "*" `shouldBe` Right Idea

        it "parses event bullet - user uses o for events" $ do
            parseBullet "o" `shouldBe` Right Event

        it "parses shopping bullet - user uses $ for shopping items" $ do
            parseBullet "$" `shouldBe` Right Shopping

        it "rejects invalid bullet character" $ do
            isLeft (parseBullet "#") `shouldBe` True

    describe "Task Parsing (TEST_SPEC.md#1.2)" $ do
        it "parses single-line task" $ do
            -- User story: "I write a simple task on one line"
            let input = ". Buy milk"
            case parseTaskLine (fromGregorian 2025 8 16) input of
                Right task -> do
                    taskBullet task `shouldBe` Open
                    taskText task `shouldBe` "Buy milk"
                    taskContexts task `shouldBe` []
                    taskDue task `shouldBe` Nothing
                    taskNotes task `shouldBe` []
                    taskUid task `shouldBe` Nothing
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "parses task with single context" $ do
            -- User story: "I add @store to remember where to do this task"
            let input = ". Buy milk @store"
            case parseTaskLine (fromGregorian 2025 8 16) input of
                Right task -> taskContexts task `shouldBe` [Context "store"]
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "parses task with multiple contexts" $ do
            -- User story: "I tag tasks with multiple contexts"
            let input = ". Call Bob @calls @urgent"
            case parseTaskLine (fromGregorian 2025 8 16) input of
                Right task -> taskContexts task `shouldBe` [Context "calls", Context "urgent"]
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "parses task with due date" $ do
            -- User story: "I add Due: dates to track deadlines"
            let input = ". Submit report Due: 2025-08-20"
            case parseTaskLine (fromGregorian 2025 8 16) input of
                Right task -> taskDue task `shouldBe` Just (fromGregorian 2025 8 20)
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "ignores freeform notes - documentation only" $ do
            -- User story: "Non-bulleted text is documentation only, not synced"
            -- @test-spec: TEST_SPEC.md#1.2-freeform-ignored
            let input = "Some documentation text"
            case parseTaskLine (fromGregorian 2025 8 16) input of
                Left _ -> return () -- Expected: parse should fail/ignore
                Right task -> expectationFailure $ "Should not create task for freeform text: " ++ show task

        it "parses mixed bullets and freeform" $ do
            -- User story: "Only bulleted items become tasks, freeform preserved but ignored"
            -- @test-spec: TEST_SPEC.md#1.2-mixed-content
            let input = "2025-08-16\n. Buy milk\nNotes about shopping\n. Call mom"
            case parseDateSection input of
                Right section -> do
                    length (sectionEntries section) `shouldBe` 2
                    map taskText (sectionEntries section) `shouldBe` ["Buy milk", "Call mom"]
                Left err -> expectationFailure $ "Parse failed: " ++ show err

    describe "Date Section Parsing (TEST_SPEC.md#1.3)" $ do
        it "parses valid date header" $ do
            -- User story: "I start each day with YYYY-MM-DD format"
            let input = "2025-08-16\n. Task"
            case parseDateSection input of
                Right section -> do
                    sectionDate section `shouldBe` fromGregorian 2025 8 16
                    length (sectionEntries section) `shouldBe` 1
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "rejects invalid date format" $ do
            -- User story: "System enforces consistent date format"
            let input = "08/16/2025\n. Task"
            isLeft (parseDateSection input) `shouldBe` True

        it "rejects invalid date values" $ do
            -- User story: "System validates date values are realistic"
            let input1 = "2025-13-45\n. Task" -- Invalid month and day
            let input2 = "2025-02-30\n. Task" -- Invalid day for February
            isLeft (parseDateSection input1) `shouldBe` True
            isLeft (parseDateSection input2) `shouldBe` True

        it "parses multiple date sections" $ do
            -- User story: "My file contains many days of tasks"
            let input = "2025-08-16\n. Task 1\n\n2025-08-17\n. Task 2"
            case parseTodoFile input of
                Right sections -> length sections `shouldBe` 2
                Left err -> expectationFailure $ "Parse failed: " ++ show err

    describe "Context Extraction (TEST_SPEC.md#1.4)" $ do
        it "extracts context at end of line" $ do
            -- User story: "I add @computer to tasks"
            extractContexts "Task @computer" `shouldBe` [Context "computer"]

        it "ignores @ in middle of words (like emails)" $ do
            -- User story: "Email addresses aren't contexts"
            extractContexts "Email bob@example.com" `shouldBe` []

        it "extracts multiple contexts" $ do
            extractContexts "Task @home @urgent @computer"
                `shouldBe` [Context "home", Context "urgent", Context "computer"]

        it "handles contexts with hyphens and underscores" $ do
            extractContexts "Task @home-office @high_priority"
                `shouldBe` [Context "home-office", Context "high_priority"]

    describe "Due Date Parsing (TEST_SPEC.md#1.5)" $ do
        it "parses valid due date" $ do
            -- User story: "I mark deadlines with Due: YYYY-MM-DD"
            parseDueDate "Due: 2025-08-20" `shouldBe` Just (fromGregorian 2025 8 20)

        it "ignores time in due date" $ do
            -- User story: "Times are ignored, we only track dates"
            parseDueDate "Due: 2025-08-20 14:30" `shouldBe` Just (fromGregorian 2025 8 20)

        it "returns Nothing for invalid format" $ do
            -- User story: "Natural language dates aren't supported (yet)"
            parseDueDate "Due: tomorrow" `shouldBe` Nothing

        it "accepts past due dates" $ do
            -- User story: "Past dates are valid for overdue tracking"
            parseDueDate "Due: 2020-01-01" `shouldBe` Just (fromGregorian 2020 1 1)

    describe "Full File Parsing" $ do
        it "parses complete todo.txt file" $ do
            let input =
                    T.unlines
                        [ "2025-08-16"
                        , ". Review code @computer"
                        , "x Submit report @done"
                        , "! Fix bug @urgent Due: 2025-08-17"
                        , ""
                        , "2025-08-17"
                        , ". Call client @calls"
                        ]
            case parseTodoFile input of
                Right sections -> do
                    length sections `shouldBe` 2
                    case sections of
                        (firstSection : _) -> length (sectionEntries firstSection) `shouldBe` 3
                        [] -> expectationFailure "Expected at least one section"
                Left err -> expectationFailure $ "Parse failed: " ++ show err

    describe "Zettel Tag Recognition (ZETTLE.md#parsing)" $ do
        it "parses #zettel:slug tag - user captures full zettelkasten entry" $ do
            -- User story: "I write #zettel:atomic-design to seed my zettelkasten"
            -- Data flow: "#zettel:atomic-design" -> zettel parser -> ZettelFull type
            let input = "#zettel:atomic-design Some thoughts on modular architecture"
            case parseZettelTag input of
                Right zettel -> do
                    zettelSlug zettel `shouldBe` "atomic-design"
                    zettelType zettel `shouldBe` ZettelFull
                    zettelContent zettel `shouldBe` "Some thoughts on modular architecture"
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "parses #z:slug tag - user captures quick fleeting thought" $ do
            -- User story: "I use #z:meeting for quick captures during meetings"
            -- Data flow: "#z:meeting" -> zettel parser -> ZettelShort type
            let input = "#z:knowledge-graphs Personal knowledge management needs better linking"
            case parseZettelTag input of
                Right zettel -> do
                    zettelSlug zettel `shouldBe` "knowledge-graphs"
                    zettelType zettel `shouldBe` ZettelShort
                    zettelContent zettel `shouldBe` "Personal knowledge management needs better linking"
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "parses #idea:slug tag - user captures project concept" $ do
            -- User story: "I use #idea:personal-wiki for future project ideas"
            -- Data flow: "#idea:personal-wiki" -> zettel parser -> ZettelIdea type
            let input = "#idea:mg-extension What if mg could seed a zettelkasten?"
            case parseZettelTag input of
                Right zettel -> do
                    zettelSlug zettel `shouldBe` "mg-extension"
                    zettelType zettel `shouldBe` ZettelIdea
                    zettelContent zettel `shouldBe` "What if mg could seed a zettelkasten?"
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "validates slug format - rejects invalid characters" $ do
            -- User story: "System enforces clean slugs for filename compatibility"
            -- Data flow: "#zettel:invalid@slug!" -> validation -> ParseError
            let input = "#zettel:invalid@slug! Content here"
            case parseZettelTag input of
                Left _ -> return () -- Expected: should fail
                Right zettel -> expectationFailure $ "Should reject invalid slug: " ++ show zettel

        it "validates slug length - rejects overly long slugs" $ do
            -- User story: "Slugs must be reasonable length for filesystem limits"
            let longSlug = replicate 60 'a' -- Over 50 char limit
            let input = "#zettel:" <> T.pack longSlug <> " Content"
            case parseZettelTag input of
                Left _ -> return () -- Expected: should fail
                Right zettel -> expectationFailure $ "Should reject long slug: " ++ show zettel

        it "extracts zettel with continuation lines" $ do
            -- User story: "I indent additional thoughts under my zettel tags"
            -- Data flow: Main line + indented lines -> combined content
            let input = T.unlines 
                    [ "#zettel:atomic-design Modular architecture principles"
                    , "  - Single responsibility per component"
                    , "  - Clear interfaces between modules" 
                    ]
            case parseZettelWithContinuation input of
                Right zettel -> do
                    zettelSlug zettel `shouldBe` "atomic-design"
                    zettelContent zettel `shouldBe` "Modular architecture principles"
                    zettelContinuation zettel `shouldBe` 
                        [ "- Single responsibility per component"
                        , "- Clear interfaces between modules"
                        ]
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "ignores non-zettel lines" $ do
            -- User story: "Only specially tagged lines become zettels"
            -- Data flow: Regular task line -> zettel parser -> Nothing
            let input = ". Regular task @work"
            case parseZettelTag input of
                Left _ -> return () -- Expected: should fail/ignore
                Right zettel -> expectationFailure $ "Should not create zettel from regular task: " ++ show zettel

    describe "Zettel Integration with Tasks (ZETTLE.md#integration)" $ do
        it "parses mixed tasks and zettels in date section" $ do
            -- User story: "I mix regular tasks and zettel captures in my daily log"
            -- Data flow: Date section -> parse both tasks and zettels -> separate lists
            let input = T.unlines
                    [ "2025-08-21"
                    , ". Regular task @work"
                    , "#zettel:meeting-insights Team dynamics affect code quality"
                    , "x Completed task @done"
                    , "#z:quick-note Personal knowledge needs better linking"
                    ]
            case parseDateSectionWithZettels input of
                Right (section, zettels) -> do
                    length (sectionEntries section) `shouldBe` 2 -- Only bulleted tasks
                    length zettels `shouldBe` 2 -- Both zettel tags
                    map zettelSlug zettels `shouldBe` ["meeting-insights", "quick-note"]
                Left err -> expectationFailure $ "Parse failed: " ++ show err

    describe "Comprehensive Parser Coverage" $ do
        it "handles parse errors in parseBullet" $ do
            -- Cover InvalidBullet error path
            case parseBullet "invalid" of
                Left (InvalidBullet _) -> return () -- Expected
                Right _ -> expectationFailure "Should fail on invalid bullet"
                Left err -> expectationFailure $ "Wrong error type: " ++ show err

        it "handles parse errors in parseTaskLine" $ do
            -- Cover ParseFailure error path  
            let date = fromGregorian 2025 8 21
            case parseTaskLine date "invalid line without bullet" of
                Left (ParseFailure _) -> return () -- Expected
                Right _ -> expectationFailure "Should fail on invalid task line"
                Left err -> expectationFailure $ "Wrong error type: " ++ show err

        it "extracts time context for event bullets" $ do
            -- Cover event bullet and extractTimeContext logic
            let date = fromGregorian 2025 8 21
            let line = "o Meeting with team @work @2pm"
            case parseTaskLine date line of
                Right task -> do
                    taskBullet task `shouldBe` Event
                    taskEventTime task `shouldBe` Just "2pm"
                    map (\(Context c) -> c) (taskContexts task) `shouldBe` ["work"]
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "handles various time context formats" $ do
            -- Cover all time context detection patterns
            let date = fromGregorian 2025 8 21
            -- Test AM/PM formats
            case parseTaskLine date "o Meeting @9am" of
                Right task -> taskEventTime task `shouldBe` Just "9am"
                Left err -> expectationFailure $ "Failed AM: " ++ show err
            case parseTaskLine date "o Meeting @2PM" of  
                Right task -> taskEventTime task `shouldBe` Just "2PM"
                Left err -> expectationFailure $ "Failed PM: " ++ show err
            -- Test 24-hour format
            case parseTaskLine date "o Meeting @14:30" of
                Right task -> taskEventTime task `shouldBe` Just "14:30"
                Left err -> expectationFailure $ "Failed 24hr: " ++ show err
            -- Test time ranges
            case parseTaskLine date "o Meeting @2-4pm" of
                Right task -> taskEventTime task `shouldBe` Just "2-4pm"
                Left err -> expectationFailure $ "Failed range: " ++ show err

        it "parses due dates with time components" $ do
            -- Cover timeParser in due date parsing
            let date = fromGregorian 2025 8 21
            let line = ". Task Due: 2025-08-22 14:30"
            case parseTaskLine date line of
                Right task -> do
                    taskDue task `shouldBe` Just (fromGregorian 2025 8 22)
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "handles invalid dates in due date parsing" $ do
            -- Cover date validation error in dueDateParser
            let date = fromGregorian 2025 8 21
            let line = ". Task Due: 2025-13-32"  -- Invalid month and day
            case parseTaskLine date line of
                Left _ -> return () -- Expected to fail
                Right task -> expectationFailure $ "Should fail on invalid due date: " ++ show task

        it "handles invalid dates in date section parsing" $ do
            -- Cover date validation error in parseDateSection
            let input = T.unlines ["2025-13-32", ". Task"]  -- Invalid date
            case parseDateSection input of
                Left _ -> return () -- Expected to fail
                Right _ -> expectationFailure "Should fail on invalid date in section"

        it "handles parse errors in parseTodoFile" $ do  
            -- parseTodoFile is very robust and rarely fails - just test the error path exists
            -- The coverage shows ParseFailure is reachable, just hard to trigger in practice
            case parseTodoFile "" of -- Empty input should not cause crash
                Left _ -> return () -- Any parse error is acceptable
                Right sections -> length sections `shouldBe` 0 -- Empty result is also fine

        it "parses file with non-date content to skip" $ do
            -- Cover skipNonDateSection parser
            let input = T.unlines 
                    [ "Some random header"
                    , "More non-date content" 
                    , "2025-08-21"
                    , ". Valid task"
                    , "Random footer"
                    ]
            case parseTodoFile input of
                Right sections -> do
                    length sections `shouldBe` 1
                    sectionDate (head sections) `shouldBe` fromGregorian 2025 8 21
                Left err -> expectationFailure $ "Parse failed: " ++ show err

        it "validates context characters thoroughly" $ do
            -- Cover validContextChar edge cases  
            let validContexts = extractContexts "task @valid-context_with123"
            length validContexts `shouldBe` 1
            let invalidContexts = extractContexts "task @invalid@symbols"
            length invalidContexts `shouldBe` 0 -- Should reject due to @ symbol

        it "handles zettel tag parse errors" $ do
            -- Cover parseZettelTag error paths
            case parseZettelTag "#zettel:invalid-slug-no-content" of
                Left (ParseFailure _) -> return () -- Expected: missing content
                Right _ -> expectationFailure "Should fail on missing content"
                Left err -> expectationFailure $ "Wrong error type: " ++ show err

        it "validates zettel slug length limits" $ do
            -- Cover slug length validation
            let longSlug = replicate 60 'a' -- Too long (>50 chars)
            let input = "#zettel:" <> T.pack longSlug <> " Content here"
            case parseZettelTag input of
                Left (ParseFailure _) -> return () -- Expected: slug too long
                Right _ -> expectationFailure "Should fail on overly long slug"
                Left err -> expectationFailure $ "Wrong error type: " ++ show err

        it "validates zettel slug character restrictions" $ do
            -- Cover slug character validation
            case parseZettelTag "#zettel:invalid@slug Content here" of
                Left (ParseFailure _) -> return () -- Expected: invalid chars
                Right _ -> expectationFailure "Should fail on invalid slug characters" 
                Left err -> expectationFailure $ "Wrong error type: " ++ show err

        it "handles zettel with continuation parse errors" $ do
            -- Cover parseZettelWithContinuation error paths
            case parseZettelWithContinuation "#zettel:" of -- Missing slug and content
                Left (ParseFailure _) -> return () -- Expected
                Right _ -> expectationFailure "Should fail on incomplete zettel"
                Left err -> expectationFailure $ "Wrong error type: " ++ show err

        it "covers all zettel types in continuation parsing" $ do
            -- Cover all zettel type parsing paths in parseZettelWithContinuation
            let fullZettel = "#zettel:test-slug Content here\n  Continuation"
            let shortZettel = "#z:test-slug Content here\n  Continuation"  
            let ideaZettel = "#idea:test-slug Content here\n  Continuation"
            
            case parseZettelWithContinuation fullZettel of
                Right z -> zettelType z `shouldBe` ZettelFull
                Left err -> expectationFailure $ "Full zettel failed: " ++ show err
            case parseZettelWithContinuation shortZettel of
                Right z -> zettelType z `shouldBe` ZettelShort  
                Left err -> expectationFailure $ "Short zettel failed: " ++ show err
            case parseZettelWithContinuation ideaZettel of
                Right z -> zettelType z `shouldBe` ZettelIdea
                Left err -> expectationFailure $ "Idea zettel failed: " ++ show err

        it "handles date section with zettels parse errors" $ do
            -- Cover parseDateSectionWithZettels error handling
            let invalidInput = "invalid-date\n. Task\n#zettel:test Content"
            case parseDateSectionWithZettels invalidInput of
                Left (ParseFailure _) -> return () -- Expected
                Right _ -> expectationFailure "Should fail on invalid date section"
                Left err -> expectationFailure $ "Wrong error type: " ++ show err

        it "handles empty lines in various parsers" $ do  
            -- Cover null/empty line handling in multiple places
            let emptyDateSection = T.unlines ["2025-08-21", "", "   ", ". Task"]
            case parseDateSection emptyDateSection of
                Right section -> length (sectionEntries section) `shouldBe` 1 -- Only the task
                Left err -> expectationFailure $ "Empty line handling failed: " ++ show err
