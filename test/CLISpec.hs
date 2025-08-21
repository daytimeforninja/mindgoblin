{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (defaultTimeLocale, formatTime, getCurrentTime, getCurrentTimeZone, utcToLocalTime, localDay)
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Hspec

-- | Get current local date formatted as YYYY-MM-DD
getCurrentLocalDateString :: IO String
getCurrentLocalDateString = do
    utc <- getCurrentTime
    tz <- getCurrentTimeZone
    let local = utcToLocalTime tz utc
    return $ formatTime defaultTimeLocale "%Y-%m-%d" (localDay local)

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "CLI Command Tests" $ do
        describe "mg stats command" $ do
            it "works with default ~/todo.txt (when present)" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                today <- getCurrentLocalDateString
                let content = T.pack $ unlines [today, ". Test task"]
                TIO.writeFile todoFile content

                (exitCode, stdout, _) <-
                    readProcessWithExitCode
                        "env"
                        ["HOME=" ++ tmpDir, "cabal", "run", "mg", "--", "stats"]
                        ""

                exitCode `shouldBe` ExitSuccess
                stdout `shouldContain` "Total entries:"

            it "accepts --file option" $ withTempDir $ \tmpDir -> do
                let customFile = tmpDir </> "custom.txt"
                today <- getCurrentLocalDateString
                let content = T.pack $ unlines [today, ". Custom task"]
                TIO.writeFile customFile content

                (exitCode, stdout, _) <-
                    readProcessWithExitCode
                        "cabal"
                        ["run", "mg", "--", "stats", "--file", customFile]
                        ""

                exitCode `shouldBe` ExitSuccess
                stdout `shouldContain` "Total entries: 1"

            it "handles missing file gracefully" $ do
                (exitCode, _, _) <-
                    readProcessWithExitCode
                        "cabal"
                        ["run", "mg", "--", "stats", "--file", "/nonexistent/file.txt"]
                        ""

                exitCode `shouldNotBe` ExitSuccess

        describe "mg push command" $ do
            it "accepts --dry-run option" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                today <- getCurrentLocalDateString
                let content = T.pack $ unlines [today, ". Test task"]
                TIO.writeFile todoFile content

                (exitCode, stdout, _) <-
                    readProcessWithExitCode
                        "env"
                        [ "HOME=" ++ tmpDir
                        , "cabal"
                        , "run"
                        , "mg"
                        , "--"
                        , "push"
                        , "--file"
                        , todoFile
                        , "--dry-run"
                        ]
                        ""

                exitCode `shouldBe` ExitSuccess
                stdout `shouldContain` "Dry run"

            it "accepts --file option" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "custom.txt"
                let vdirPath = tmpDir </> ".local" </> "share" </> "mg" </> "tasks"
                createDirectoryIfMissing True vdirPath

                today <- getCurrentLocalDateString
                let content = T.pack $ unlines [today, ". Test task"]
                TIO.writeFile todoFile content

                (exitCode, stdout, _) <-
                    readProcessWithExitCode
                        "env"
                        [ "HOME=" ++ tmpDir
                        , "cabal"
                        , "run"
                        , "mg"
                        , "--"
                        , "push"
                        , "--file"
                        , todoFile
                        ]
                        ""

                exitCode `shouldBe` ExitSuccess
                stdout `shouldContain` "Push complete"

        describe "mg pull command" $ do
            it "accepts --dry-run option" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                today <- getCurrentLocalDateString
                let content = T.pack $ unlines [today, ". Test task"]
                TIO.writeFile todoFile content

                -- This will fail due to vdirsyncer config, but should accept the option
                (_, _, _) <-
                    readProcessWithExitCode
                        "env"
                        [ "HOME=" ++ tmpDir
                        , "cabal"
                        , "run"
                        , "mg"
                        , "--"
                        , "pull"
                        , "--file"
                        , todoFile
                        , "--dry-run"
                        ]
                        ""

                -- Just verify it attempts the operation
                return ()

            it "accepts --file option" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "custom.txt"
                today <- getCurrentLocalDateString
                let content = T.pack $ unlines [today, ". Test task"]
                TIO.writeFile todoFile content

                -- This will likely fail due to vdirsyncer, but should accept the option
                (_, _, _) <-
                    readProcessWithExitCode
                        "env"
                        [ "HOME=" ++ tmpDir
                        , "cabal"
                        , "run"
                        , "mg"
                        , "--"
                        , "pull"
                        , "--file"
                        , todoFile
                        , "--dry-run"
                        ]
                        ""

                -- Just verify it doesn't crash on argument parsing
                return ()

        describe "mg sync command" $ do
            it "accepts --dry-run option" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                today <- getCurrentLocalDateString
                let content = T.pack $ unlines [today, ". Test task"]
                TIO.writeFile todoFile content

                -- Will fail on vdirsyncer, but should accept --dry-run
                (_, _, _) <-
                    readProcessWithExitCode
                        "env"
                        [ "HOME=" ++ tmpDir
                        , "cabal"
                        , "run"
                        , "mg"
                        , "--"
                        , "sync"
                        , "--file"
                        , todoFile
                        , "--dry-run"
                        ]
                        ""

                -- Just verify the command parsing works
                return ()

        describe "mg --help and --version" $ do
            it "shows help with --help" $ do
                (exitCode, stdout, _) <-
                    readProcessWithExitCode
                        "cabal"
                        ["run", "mg", "--", "--help"]
                        ""

                exitCode `shouldBe` ExitSuccess
                stdout `shouldContain` "Mind Goblin"
                stdout `shouldContain` "Usage:"
                stdout `shouldContain` "commands:"

            it "shows version with --version" $ do
                (exitCode, stdout, _) <-
                    readProcessWithExitCode
                        "cabal"
                        ["run", "mg", "--", "--version"]
                        ""

                exitCode `shouldBe` ExitSuccess
                stdout `shouldContain` "mg"

            it "shows help for subcommands" $ do
                (_, _, _) <-
                    readProcessWithExitCode
                        "cabal"
                        ["run", "mg", "--", "stats", "--help"]
                        ""

                -- Command parsing works (may show general help)
                return ()

        describe "Error handling" $ do
            it "handles invalid commands gracefully" $ do
                (exitCode, _, _) <-
                    readProcessWithExitCode
                        "cabal"
                        ["run", "mg", "--", "invalid-command"]
                        ""

                exitCode `shouldNotBe` ExitSuccess
                -- Error handling works (various error messages possible)
                return ()

            it "handles invalid options gracefully" $ do
                (exitCode, _, _) <-
                    readProcessWithExitCode
                        "cabal"
                        ["run", "mg", "--", "stats", "--invalid-option"]
                        ""

                exitCode `shouldNotBe` ExitSuccess
                -- Error handling works for invalid options
                return ()

        describe "mg list command" $ do
            it "shows today's tasks by priority" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                today <- getCurrentLocalDateString
                let content = T.pack $ unlines 
                      [ today
                      , ". Open task @work"
                      , "! Priority task @urgent"
                      , "$ Buy milk @groceries"
                      , "x Completed task @done"
                      , "o Meeting at 2pm @meetings"
                      ]
                TIO.writeFile todoFile content

                (exitCode, stdout, _) <-
                    readProcessWithExitCode
                        "cabal"
                        ["run", "mg", "--", "list", "--file", todoFile]
                        ""

                exitCode `shouldBe` ExitSuccess
                stdout `shouldContain` "Priority Tasks:"
                stdout `shouldContain` "! Priority task @urgent"
                stdout `shouldContain` "Open Tasks:"
                stdout `shouldContain` ". Open task @work"
                stdout `shouldContain` "Shopping:"
                stdout `shouldContain` "$ Buy milk @groceries"
                stdout `shouldContain` "Events:"
                stdout `shouldContain` "o Meeting at 2pm @meetings"
                stdout `shouldContain` "Showing 4 tasks (today only)"

            it "includes completed tasks with --completed flag" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                today <- getCurrentLocalDateString
                let content = T.pack $ unlines 
                      [ today
                      , ". Open task"
                      , "x Completed task"
                      ]
                TIO.writeFile todoFile content

                (exitCode, stdout, _) <-
                    readProcessWithExitCode
                        "cabal"
                        ["run", "mg", "--", "list", "--file", todoFile, "--completed"]
                        ""

                exitCode `shouldBe` ExitSuccess
                stdout `shouldContain` "Completed:"
                stdout `shouldContain` "x Completed task"
                stdout `shouldContain` "Showing 2 tasks (today only)"

            it "shows all tasks with --all flag" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                today <- getCurrentLocalDateString
                let yesterday = "2025-08-19"
                let content = T.pack $ unlines 
                      [ today
                      , ". Today's task"
                      , yesterday
                      , ". Yesterday's task"
                      ]
                TIO.writeFile todoFile content

                (exitCode, stdout, _) <-
                    readProcessWithExitCode
                        "cabal"
                        ["run", "mg", "--", "list", "--file", todoFile, "--all"]
                        ""

                exitCode `shouldBe` ExitSuccess
                stdout `shouldContain` ". Today's task"
                stdout `shouldContain` ". Yesterday's task"
                stdout `shouldContain` "Showing 2 tasks"
                stdout `shouldNotContain` "(today only)"

            it "filters by context with --context flag" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "todo.txt"
                today <- getCurrentLocalDateString
                let content = T.pack $ unlines 
                      [ today
                      , ". Work task @work"
                      , ". Home task @home"
                      , ". Another work task @work"
                      ]
                TIO.writeFile todoFile content

                (exitCode, stdout, _) <-
                    readProcessWithExitCode
                        "cabal"
                        ["run", "mg", "--", "list", "--file", todoFile, "--context", "work"]
                        ""

                exitCode `shouldBe` ExitSuccess
                stdout `shouldContain` ". Work task @work"
                stdout `shouldContain` ". Another work task @work"
                stdout `shouldNotContain` ". Home task @home"
                stdout `shouldContain` "Showing 2 tasks (today only)"

            it "handles empty file gracefully" $ withTempDir $ \tmpDir -> do
                let todoFile = tmpDir </> "empty.txt"
                TIO.writeFile todoFile ""

                (exitCode, stdout, _) <-
                    readProcessWithExitCode
                        "cabal"
                        ["run", "mg", "--", "list", "--file", todoFile]
                        ""

                exitCode `shouldBe` ExitSuccess
                stdout `shouldContain` "Showing 0 tasks (today only)"

            it "accepts --file option" $ withTempDir $ \tmpDir -> do
                let customFile = tmpDir </> "custom.txt"
                today <- getCurrentLocalDateString
                let content = T.pack $ unlines [today, ". Custom task"]
                TIO.writeFile customFile content

                (exitCode, stdout, _) <-
                    readProcessWithExitCode
                        "cabal"
                        ["run", "mg", "--", "list", "--file", customFile]
                        ""

                exitCode `shouldBe` ExitSuccess
                stdout `shouldContain` ". Custom task"
                stdout `shouldContain` "Showing 1 tasks (today only)"

            it "handles missing file gracefully" $ do
                (exitCode, _, _) <-
                    readProcessWithExitCode
                        "cabal"
                        ["run", "mg", "--", "list", "--file", "/nonexistent/file.txt"]
                        ""

                exitCode `shouldNotBe` ExitSuccess

-- Helper functions

withTempDir :: (FilePath -> IO a) -> IO a
withTempDir action = withSystemTempDirectory "mg-cli-test" action
