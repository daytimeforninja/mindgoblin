{-# LANGUAGE OverloadedStrings #-}

module MindGoblin.VDirSyncer
  ( runVdirsyncer
  , VdirsyncerError(..)
  ) where

import System.Process (readProcessWithExitCode)
import System.Exit (ExitCode(..))
import Control.Exception (Exception, throwIO)
import Control.Monad (when)
import Data.Typeable (Typeable)

-- | VDirSyncer operation errors
data VdirsyncerError = VdirsyncerError
  { vdirsyncerCommand :: String
  , vdirsyncerExitCode :: Int
  , vdirsyncerStdout :: String
  , vdirsyncerStderr :: String
  } deriving (Show, Typeable)

instance Exception VdirsyncerError

-- | Run vdirsyncer subprocess
-- @implements: README.md#vdirsyncer-integration
-- @user-story: Users rely on vdirsyncer for CalDAV operations
-- @data-flow: mg command -> vdirsyncer subprocess -> CalDAV sync
runVdirsyncer :: String -> IO ()
runVdirsyncer command = do
  let args = words command
  putStrLn $ "Running: vdirsyncer " ++ command
  
  (exitCode, stdout, stderr) <- readProcessWithExitCode "vdirsyncer" args ""
  
  case exitCode of
    ExitSuccess -> do
      putStrLn "vdirsyncer completed successfully"
      when (not $ null stdout) $ putStrLn stdout
    ExitFailure code -> do
      putStrLn $ "vdirsyncer failed with exit code: " ++ show code
      when (not $ null stderr) $ putStrLn $ "Error: " ++ stderr
      when (not $ null stdout) $ putStrLn $ "Output: " ++ stdout
      throwIO $ VdirsyncerError command code stdout stderr

