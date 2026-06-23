module Main (main) where

import DirenvNixAllow
  ( bashHook,
    materialize,
    printCurrentIdentity,
    usage,
  )
import System.Environment (getArgs)
import System.Exit (exitFailure)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["hook", "bash"] -> putStr bashHook
    ["materialize"] -> materialize False
    ["materialize", "--quiet"] -> materialize True
    ["identity"] -> printCurrentIdentity
    ["help"] -> putStr usage
    ["--help"] -> putStr usage
    [] -> putStr usage
    _ -> do
      putStrLn usage
      exitFailure
