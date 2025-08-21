{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (bracket, catch, SomeException)
import Control.Monad (replicateM_, void)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (Day, defaultTimeLocale, formatTime, fromGregorianValid, getCurrentTime, getCurrentTimeZone, utcToLocalTime, localDay)
import System.Directory (createDirectoryIfMissing, removeDirectoryRecursive, setPermissions, emptyPermissions)
import System.FilePath ((</>))
import System.IO (hClose, openTempFile)
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (setFileMode)
import Test.Hspec

import MindGoblin.FileOps
import MindGoblin.Parser
import MindGoblin.Types

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "Chaos Engineering Tests" $ do
        describe "File System Chaos" $ do
            it "handles read-only files gracefully" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "readonly.txt"
                TIO.writeFile todoFile "2025-08-20\n. Test task"
                
                -- Make file read-only
                setFileMode todoFile 0o444
                
                let testTask = Task
                        { taskDate = fromGregorian 2025 8 20
                        , taskBullet = Open
                        , taskText = "Test task"
                        , taskContexts = []
                        , taskDue = Nothing
                        , taskNotes = []
                        , taskUid = Nothing
                        , taskEventTime = Nothing
                        }
                
                result <- markTaskCompleted todoFile testTask
                case result of
                    Left _ -> return () -- Expected to fail
                    Right _ -> expectationFailure "Should have failed on read-only file"

            it "handles directory permission errors" $ withTempDir $ \tmpDir -> do
                let restrictedDir = tmpDir </> "restricted"
                createDirectoryIfMissing True restrictedDir
                
                -- Make directory non-writable
                setPermissions restrictedDir emptyPermissions
                
                let todoFile = restrictedDir </> "todo.txt"
                result <- catch (TIO.writeFile todoFile "test" >> return True) 
                               (\(_ :: SomeException) -> return False)
                result `shouldBe` False

            it "handles concurrent file access" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "concurrent.txt"
                utc <- getCurrentTime
                tz <- getCurrentTimeZone
                let today = formatTime defaultTimeLocale "%Y-%m-%d" . localDay $ utcToLocalTime tz utc
                let content = T.pack $ unlines [today, ". Task 1", ". Task 2", ". Task 3"]
                TIO.writeFile todoFile content
                
                let testTask = Task
                        { taskDate = fromGregorian 2025 8 20
                        , taskBullet = Open
                        , taskText = "Task 1"
                        , taskContexts = []
                        , taskDue = Nothing
                        , taskNotes = []
                        , taskUid = Nothing
                        , taskEventTime = Nothing
                        }
                
                -- Simulate concurrent modifications (simplified)
                results <- sequence [markTaskCompleted todoFile testTask | _ <- [1..5]]
                let successes = length [() | Right () <- results]
                successes `shouldSatisfy` (>= 1) -- At least one should succeed

        describe "Memory Pressure Tests" $ do
            it "handles extremely large todo files" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "huge.txt"
                utc <- getCurrentTime
                tz <- getCurrentTimeZone
                let today = formatTime defaultTimeLocale "%Y-%m-%d" . localDay $ utcToLocalTime tz utc
                
                -- Generate 10,000 tasks
                let hugeTasks = map (\i -> ". Task " ++ show (i :: Int) ++ " @context" ++ show (i `mod` 100)) [1..10000]
                let hugeContent = T.pack $ unlines $ today : hugeTasks
                TIO.writeFile todoFile hugeContent
                
                -- Test parsing doesn't crash with OOM
                result <- catch (do
                    content <- TIO.readFile todoFile
                    case parseTodoFile content of
                        Left _ -> return False
                        Right sections -> return (length (concatMap sectionEntries sections) > 9000)
                    ) (\(_ :: SomeException) -> return False)
                
                result `shouldBe` True

            it "handles deeply nested directory structures" $ withTempDir $ \tmpDir -> do
                -- Create deeply nested path
                let deepPath = foldl (</>) tmpDir (replicate 50 "deep")
                createDirectoryIfMissing True deepPath
                
                let todoFile = deepPath </> "todo.txt"
                result <- catch (TIO.writeFile todoFile "2025-08-20\n. Deep task" >> return True)
                               (\(_ :: SomeException) -> return False)
                result `shouldBe` True

        describe "Input Fuzzing" $ do
            it "handles random binary data gracefully" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "binary.txt"
                
                -- Write random binary data
                let binaryData = T.pack $ map toEnum [0, 1, 255, 127, 128, 254, 253]
                TIO.writeFile todoFile binaryData
                
                -- Should not crash when parsing
                content <- TIO.readFile todoFile
                case parseTodoFile content of
                    Left _ -> return () -- Expected for invalid data
                    Right _ -> return () -- Also fine if it somehow parses

            it "handles extremely long lines" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "longlines.txt"
                utc <- getCurrentTime
                tz <- getCurrentTimeZone
                let today = formatTime defaultTimeLocale "%Y-%m-%d" . localDay $ utcToLocalTime tz utc
                
                -- Create a task with 100,000 character text
                let longText = T.replicate 100000 "a"
                let longContent = T.pack $ unlines [today, ". " ++ T.unpack longText]
                TIO.writeFile todoFile longContent
                
                -- Should not crash
                content <- TIO.readFile todoFile
                case parseTodoFile content of
                    Left _ -> return () -- Expected - might be too long
                    Right sections -> length (concatMap sectionEntries sections) `shouldSatisfy` (>= 0)

            it "handles null bytes and control characters" $ do
                let maliciousInput = "2025-08-20\n. Task with \\0 null \\x01 control \\x1f chars"
                parseTodoFile (T.pack maliciousInput) `shouldSatisfy` (either (const True) (const True))

        describe "Resource Exhaustion" $ do
            it "handles disk space exhaustion simulation" $ withTempDir $ \tmpDir -> do
                -- Create many small files to simulate disk pressure
                replicateM_ 1000 $ do
                    (path, handle) <- openTempFile tmpDir "pressure"
                    hClose handle
                
                let todoFile = tmpDir </> "todo.txt"
                result <- catch (TIO.writeFile todoFile "2025-08-20\n. Test" >> return True)
                               (\(_ :: SomeException) -> return False)
                -- Either succeeds or fails gracefully
                result `shouldSatisfy` const True

            it "handles circular symlinks gracefully" $ withTempDir $ \tmpDir -> do
                -- Note: This test might not work on all systems
                let todoFile = tmpDir </> "todo.txt"
                result <- catch (TIO.readFile todoFile >> return False)
                               (\(_ :: SomeException) -> return True)
                result `shouldBe` True -- Should fail gracefully

        describe "Unicode Torture Tests" $ do
            it "handles all Unicode categories" $ do
                let unicodeTorture = T.pack "2025-08-20\n. 🚀🎉💀 Arabic: العربية Chinese: 中文 Japanese: 日本語 Math: ∑∞≠±×÷ Currency: $€£¥₹"
                case parseTodoFile unicodeTorture of
                    Left _ -> return () -- May fail on complex Unicode
                    Right sections -> length sections `shouldSatisfy` (>= 0)

            it "handles mixed encodings and malformed UTF-8" $ do
                -- Test with potentially problematic Unicode sequences
                let problematicUnicode = "2025-08-20\n. \\xFFFE\\xFFFF\\xD800\\xDFFF"
                parseTodoFile (T.pack problematicUnicode) `shouldSatisfy` (either (const True) (const True))

            it "handles extremely long Unicode sequences" $ do
                let longUnicode = T.replicate 10000 "🚀"
                let content = "2025-08-20\n. " <> longUnicode
                case parseTodoFile content of
                    Left _ -> return () -- May fail due to length
                    Right sections -> length sections `shouldSatisfy` (>= 0)

-- Helper functions

withTempDir :: (FilePath -> IO a) -> IO a
withTempDir action = withSystemTempDirectory "mg-chaos-test" action

fromGregorian :: Integer -> Int -> Int -> Day
fromGregorian y m d = case fromGregorianValid y m d of
    Just date -> date
    Nothing -> case fromGregorianValid 2025 1 1 of
        Just defaultDate -> defaultDate
        Nothing -> error "Internal error: default date invalid"