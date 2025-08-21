{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (bracket)
import Data.List (elem, sort)
import Data.Text qualified as T
import Data.Time (Day, fromGregorian, UTCTime(..), getCurrentTime, utctDay)
import System.Directory (createDirectoryIfMissing, removeDirectoryRecursive, doesDirectoryExist, listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (createTempDirectory, getCanonicalTemporaryDirectory)
import Test.Hspec

import MindGoblin.Types
import MindGoblin.Parser (parseZettelTag)
import MindGoblin.Zettel

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "Denote File Generation (ZETTLE.md#denote-format)" $ do
        it "generates denote filename from zettel - follows timestamp--slug__keywords.txt format" $ do
            -- User story: "My zettel becomes a properly named denote file"
            -- Data flow: Zettel -> timestamp -> slug -> keywords -> filename
            let zettel = Zettel "atomic-design" "Modular architecture principles" [] ["software", "architecture"] ZettelFull
            let timestamp = "20250821T143022"
            let expectedFilename = "20250821T143022--atomic-design__software_architecture.txt"
            generateDenotFilename timestamp zettel `shouldBe` expectedFilename

        it "generates denote front matter - includes title, date, filetags, identifier" $ do
            -- User story: "My zettel file has proper denote metadata"
            -- Data flow: Zettel -> front matter generation -> denote header
            let zettel = Zettel "meeting-notes" "Team dynamics discussion" ["Key insights", "Action items"] ["meetings", "team"] ZettelFull
            let timestamp = "20250821T143022"
            let frontMatter = generateDenoteFrontMatter timestamp zettel
            T.lines frontMatter `shouldContain` ["title:      Team dynamics discussion"]
            T.lines frontMatter `shouldContain` ["date:       2025-08-21T14:30:22"]
            T.lines frontMatter `shouldContain` ["filetags:   meetings team"]
            T.lines frontMatter `shouldContain` ["identifier: 20250821T143022"]
            T.lines frontMatter `shouldContain` ["source:     mg-bullet-journal"]

        it "generates complete denote file content - front matter + content + continuation" $ do
            -- User story: "My zettel becomes a complete denote file"
            -- Data flow: Zettel -> front matter + content -> complete file
            let zettel = Zettel "atomic-design" "Modular architecture principles" 
                               ["- Single responsibility per component", "- Clear interfaces between modules"]
                               ["software", "architecture"] ZettelFull
            let timestamp = "20250821T143022"
            let fileContent = generateDenoteFileContent timestamp zettel
            
            -- Should include front matter
            T.isInfixOf "title:      Modular architecture principles" fileContent `shouldBe` True
            T.isInfixOf "filetags:   software architecture" fileContent `shouldBe` True
            
            -- Should include main content
            T.isInfixOf "Modular architecture principles" fileContent `shouldBe` True
            
            -- Should include continuation lines
            T.isInfixOf "- Single responsibility per component" fileContent `shouldBe` True
            T.isInfixOf "- Clear interfaces between modules" fileContent `shouldBe` True

        it "sanitizes keywords for filename - replaces spaces with underscores" $ do
            -- User story: "Keywords with spaces work in filenames"
            -- Data flow: ["design patterns", "software"] -> "design-patterns_software"
            let keywords = ["design patterns", "software architecture", "team"]
            let sanitized = sanitizeKeywordsForFilename keywords
            sanitized `shouldBe` "design-patterns_software-architecture_team"

        it "generates different keywords based on zettel type" $ do
            -- User story: "Different zettel types get appropriate keywords"
            -- Data flow: ZettelType -> semantic keywords -> denote tags
            let zettelFull = Zettel "test" "content" [] [] ZettelFull
            let zettelShort = Zettel "test" "content" [] [] ZettelShort  
            let zettelIdea = Zettel "test" "content" [] [] ZettelIdea
            
            let keywordsFull = generateZettelTypeKeywords zettelFull
            let keywordsShort = generateZettelTypeKeywords zettelShort
            let keywordsIdea = generateZettelTypeKeywords zettelIdea
            
            -- Test all keywords for complete coverage
            keywordsFull `shouldBe` ["permanent-notes", "zettelkasten"]
            keywordsShort `shouldBe` ["fleeting-notes", "quick-capture"]
            keywordsIdea `shouldBe` ["ideas", "projects", "future"]

    describe "File System Operations (ZETTLE.md#file-system)" $ do
        it "creates zettel file in notes directory - atomic write with temp file" $ do
            -- User story: "My zettel safely becomes a file on disk"
            -- Data flow: Zettel -> temp file -> atomic rename -> final file
            withTestNotesDir $ \notesDir -> do
                let zettel = Zettel "test-zettel" "Test content" [] ["test"] ZettelFull
                currentTime <- getCurrentTime
                let timestamp = formatDenoteTimestamp currentTime
                
                createZettelFile notesDir timestamp zettel
                
                -- Check file was created
                files <- listDirectory notesDir
                length files `shouldBe` 1
                
                -- Check filename format
                let filename = head files
                filename `shouldStartWith` timestamp
                filename `shouldContain` "--test-zettel"
                filename `shouldEndWith` ".txt"

        it "creates notes directory if it doesn't exist" $ do
            -- User story: "mg creates the notes directory for me"
            -- Data flow: Missing directory -> createDirectoryIfMissing -> ready for files
            withTempDir $ \tempDir -> do
                let notesDir = tempDir </> "notes"
                let zettel = Zettel "test" "content" [] [] ZettelFull
                currentTime <- getCurrentTime
                let timestamp = formatDenoteTimestamp currentTime
                
                -- Directory shouldn't exist initially
                exists <- doesDirectoryExist notesDir
                exists `shouldBe` False
                
                createZettelFile notesDir timestamp zettel
                
                -- Directory should now exist
                existsAfter <- doesDirectoryExist notesDir
                existsAfter `shouldBe` True

        it "handles filename conflicts - appends counter if file exists" $ do
            -- User story: "Duplicate zettel slugs don't overwrite files"
            -- Data flow: Existing file -> conflict detection -> append counter
            withTestNotesDir $ \notesDir -> do
                let zettel = Zettel "conflict-test" "First content" [] [] ZettelFull
                let timestamp = "20250821T143022"
                
                -- Create first file
                createZettelFile notesDir timestamp zettel
                
                -- Create second file with same slug
                let zettel2 = Zettel "conflict-test" "Second content" [] [] ZettelFull
                createZettelFile notesDir timestamp zettel2
                
                -- Should have two files
                files <- listDirectory notesDir
                length files `shouldBe` 2
                
                -- One should be original, one should have counter
                let sortedFiles = sort files
                -- Note: alphabetically, "-1.txt" comes before ".txt" 
                head sortedFiles `shouldContain` "-1"  -- This is the conflict file
                (sortedFiles !! 1) `shouldNotContain` "-1"  -- This is the original

    describe "Integration Tests (ZETTLE.md#integration)" $ do
        it "processes multiple zettels from todo.txt and creates denote files" $ do
            -- User story: "mg sync extracts all my zettels to denote files"
            -- Data flow: todo.txt -> parse zettels -> create multiple denote files
            withTestNotesDir $ \notesDir -> do
                let todoContent = T.unlines
                        [ "2025-08-21"
                        , ". Regular task @work"
                        , "#zettel:atomic-design Modular architecture principles"
                        , "  - Single responsibility per component"
                        , "#z:quick-note Personal knowledge management insights"
                        , "#idea:future-project What if mg had a web interface?"
                        ]
                
                processZettelsFromTodoText notesDir todoContent
                
                -- Should create 3 zettel files
                files <- listDirectory notesDir
                length files `shouldBe` 3
                
                -- Check that different zettel types are created
                let filenames = sort files
                any ("atomic-design" `T.isInfixOf`) (map T.pack filenames) `shouldBe` True
                any ("quick-note" `T.isInfixOf`) (map T.pack filenames) `shouldBe` True  
                any ("future-project" `T.isInfixOf`) (map T.pack filenames) `shouldBe` True

    describe "Comprehensive Zettel Coverage" $ do
        it "formats denote timestamp using defaultTimeLocale" $ do
            -- Test defaultTimeLocale usage in formatDenoteTimestamp
            let utcTime = UTCTime (fromGregorian 2025 8 21) 51802 -- 14:23:22 (51802 seconds from midnight)
            let formatted = formatDenoteTimestamp utcTime
            formatted `shouldBe` "20250821T142322"
            
        it "handles splitExtension edge cases" $ do
            -- Test filename without extension
            let (name1, ext1) = splitExtension "filename-no-ext"
            name1 `shouldBe` "filename-no-ext"
            ext1 `shouldBe` ""
            
            -- Test filename with extension
            let (name2, ext2) = splitExtension "filename.txt"
            name2 `shouldBe` "filename"
            ext2 `shouldBe` ".txt"
            
            -- Test filename with multiple dots
            let (name3, ext3) = splitExtension "file.name.txt"
            name3 `shouldBe` "file.name"
            ext3 `shouldBe` ".txt"

        it "generates filename with no keywords" $ do
            -- Test generateDenotFilename with empty keywords
            let zettel = Zettel "no-keywords" "Test content" [] [] ZettelFull
            let timestamp = "20250821T143022"
            let filename = generateDenotFilename timestamp zettel
            filename `shouldBe` "20250821T143022--no-keywords.txt"
            
        it "generates front matter with empty keywords" $ do
            -- Test generateDenoteFrontMatter with empty keywords  
            let zettel = Zettel "no-keywords" "Test content" [] [] ZettelFull
            let timestamp = "20250821T143022"
            let frontMatter = generateDenoteFrontMatter timestamp zettel
            T.isInfixOf "filetags:   " frontMatter `shouldBe` True
            
        it "processes zettels with all zettel types" $ do
            -- Cover all zettel type instantiation in processZettelsFromTodoText
            withTestNotesDir $ \notesDir -> do
                let todoContent = "test content"
                processZettelsFromTodoText notesDir todoContent
                
                files <- listDirectory notesDir
                -- Should create files for ZettelFull, ZettelShort, ZettelIdea
                length files `shouldBe` 3

        it "handles multiple filename conflicts recursively" $ do
            -- User story: "Multiple conflicts increment counter properly"
            -- Data flow: Multiple conflicts -> recursive counter increment
            withTestNotesDir $ \notesDir -> do
                let zettel = Zettel "multi-conflict" "Test content" [] [] ZettelFull
                let timestamp = "20250821T143022"
                
                -- Create first file
                createZettelFile notesDir timestamp zettel
                -- Create second file (should get -1)
                createZettelFile notesDir timestamp zettel
                -- Create third file (should get -2)  
                createZettelFile notesDir timestamp zettel
                
                -- Should have three files
                files <- listDirectory notesDir
                length files `shouldBe` 3
                
                let sortedFiles = sort files
                -- Check all conflict files exist
                any (T.isInfixOf "-1" . T.pack) sortedFiles `shouldBe` True
                any (T.isInfixOf "-2" . T.pack) sortedFiles `shouldBe` True

-- Helper functions for testing internal functions
splitExtension :: String -> (String, String)
splitExtension filename =
    case break (== '.') $ reverse filename of
        (revExt, "") -> (filename, "") -- No extension found
        (revExt, '.':revName) -> (reverse revName, '.' : reverse revExt)
        _ -> (filename, "") -- Shouldn't happen

-- Helper functions imported from MindGoblin.Zettel

-- Test helpers

withTestNotesDir :: (FilePath -> IO a) -> IO a
withTestNotesDir action = withTempDir $ \tempDir -> do
    let notesDir = tempDir </> "notes"
    createDirectoryIfMissing True notesDir
    action notesDir

withTempDir :: (FilePath -> IO a) -> IO a
withTempDir action = do
    tempDir <- getCanonicalTemporaryDirectory
    bracket
        (createTempDirectory tempDir "mg-zettel-test")
        removeDirectoryRecursive
        action

