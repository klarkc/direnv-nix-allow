{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}

module DirenvNixAllow
  ( BoringEnvrc (..),
    bashHook,
    computeIdentity,
    direnvFileHashFromBytes,
    findEnvrc,
    findStringKey,
    isAllowedLine,
    materialize,
    normalizeLine,
    parseBoringEnvrc,
    parseFlakeRef,
    printCurrentIdentity,
    usage,
  )
where

import Control.Applicative ((<|>))
import Control.Exception (IOException, catch)
import Control.Monad (filterM, forM, unless, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson (Value (..), eitherDecodeStrict')
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.Foldable (toList)
import Data.List (find, intercalate, isPrefixOf, sort)
import Data.Maybe (catMaybes, fromMaybe)
import Data.Text qualified as Text
import Numeric (showHex)
import System.Directory
  ( canonicalizePath,
    doesDirectoryExist,
    doesFileExist,
    getCurrentDirectory,
    getHomeDirectory,
    listDirectory,
  )
import System.Directory qualified as Directory
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..), exitFailure, exitSuccess)
import System.FilePath
  ( dropFileName,
    normalise,
    takeFileName,
    (</>),
  )
import System.Process (readProcessWithExitCode)

usage :: String
usage =
  unlines
    [ "direnv-nix-allow",
      "",
      "Commands:",
      "  hook bash             Print a Bash hook wrapping direnv",
      "  materialize [--quiet] Materialize direnv approval for an equivalent Nix identity",
      "  identity              Print the current boring Nix .envrc identity",
      "  help                  Show this help"
    ]

bashHook :: String
bashHook =
  unlines
    [ "_direnv_nix_allow_hook() {",
      "  local previous_exit_status=$?",
      "  if command -v direnv-nix-allow >/dev/null 2>&1; then",
      "    direnv-nix-allow materialize --quiet >/dev/null 2>&1 || true",
      "  fi",
      "  eval \"$(direnv export bash)\"",
      "  return $previous_exit_status",
      "}",
      "case \";${PROMPT_COMMAND:-};\" in",
      "  *\";_direnv_nix_allow_hook;\"*) ;;",
      "  *) PROMPT_COMMAND=\"_direnv_nix_allow_hook${PROMPT_COMMAND:+;${PROMPT_COMMAND}}\" ;;",
      "esac"
    ]

materialize :: Bool -> IO ()
materialize quiet = do
  current <- findEnvrc =<< getCurrentDirectory
  case current of
    Nothing -> exitSuccess
    Just rc -> do
      allowed <- isDirenvAllowed rc
      when allowed exitSuccess
      currentIdentity <- computeIdentity rc
      allowedRcs <- listAllowedEnvrcs
      candidates <- forM allowedRcs $ \candidate -> do
        same <- samePath rc candidate
        if same
          then pure Nothing
          else do
            candidateAllowed <- isDirenvAllowed candidate
            if not candidateAllowed
              then pure Nothing
              else do
                candidateIdentity <- tryComputeIdentity candidate
                pure ((candidate,) <$> candidateIdentity)
      case find ((== currentIdentity) . snd) (catMaybes candidates) of
        Nothing -> do
          unless quiet $ putStrLn "No equivalent allowed Nix .envrc found."
          exitSuccess
        Just (matched, _) -> do
          (code, out, err) <- readProcessWithExitCode "direnv" ["allow", rc] ""
          case code of
            ExitSuccess -> unless quiet $ putStrLn ("Allowed via equivalent Nix identity from " <> matched)
            ExitFailure _ -> do
              unless quiet $ do
                putStr out
                putStr err
              exitFailure

printCurrentIdentity :: IO ()
printCurrentIdentity = do
  current <- findEnvrc =<< getCurrentDirectory
  case current of
    Nothing -> do
      putStrLn "No .envrc found."
      exitFailure
    Just rc -> do
      identity <- computeIdentity rc
      putStrLn identity

findEnvrc :: FilePath -> IO (Maybe FilePath)
findEnvrc dir = do
  absolute <- canonicalizePath dir
  go absolute
  where
    go path = do
      let candidate = path </> ".envrc"
      exists <- doesFileExist candidate
      if exists
        then Just <$> canonicalizePath candidate
        else
          let parent = dropTrailingPathSeparatorLike (dropFileName path)
           in if parent == path || null parent
                then pure Nothing
                else go parent

dropTrailingPathSeparatorLike :: FilePath -> FilePath
dropTrailingPathSeparatorLike path =
  case reverse path of
    '/' : rest -> reverse rest
    _ -> path

samePath :: FilePath -> FilePath -> IO Bool
samePath a b = do
  ca <- canonicalizePath a
  cb <- canonicalizePath b
  pure (ca == cb)

isDirenvAllowed :: FilePath -> IO Bool
isDirenvAllowed rc = do
  allow <- direnvAllowPath rc
  doesFileExist allow

direnvAllowPath :: FilePath -> IO FilePath
direnvAllowPath rc = do
  allowDir <- direnvAllowDir
  hash <- direnvFileHash rc
  pure (allowDir </> hash)

direnvAllowDir :: IO FilePath
direnvAllowDir = do
  xdg <- lookupEnv "XDG_DATA_HOME"
  home <- getHomeDirectory
  pure (fromMaybe (home </> ".local" </> "share") xdg </> "direnv" </> "allow")

direnvFileHash :: FilePath -> IO String
direnvFileHash rc = do
  absolute <- canonicalizePath rc
  bytes <- BS.readFile absolute
  pure (direnvFileHashFromBytes absolute bytes)

direnvFileHashFromBytes :: FilePath -> BS.ByteString -> String
direnvFileHashFromBytes absolute bytes =
  hex (SHA256.hash (BS8.pack absolute <> BS8.pack "\n" <> bytes))

hex :: BS.ByteString -> String
hex = concatMap byteHex . BS.unpack
  where
    byteHex byte =
      let rendered = showHex byte ""
       in if length rendered == 1 then '0' : rendered else rendered

listAllowedEnvrcs :: IO [FilePath]
listAllowedEnvrcs = do
  allowDir <- direnvAllowDir
  exists <- doesDirectoryExist allowDir
  if not exists
    then pure []
    else do
      entries <- listDirectory allowDir
      paths <- forM entries $ \entry -> do
        let allowFile = allowDir </> entry
        content <- safeReadFile allowFile
        pure (normalise . takeWhile (/= '\n') <$> content)
      existing <- filterM doesFileExist (catMaybes paths)
      pure [path | path <- existing, takeFileName path == ".envrc"]

safeReadFile :: FilePath -> IO (Maybe String)
safeReadFile path = (Just <$> readFile path) `catch` (\(_ :: IOException) -> pure Nothing)

tryComputeIdentity :: FilePath -> IO (Maybe String)
tryComputeIdentity path = (Just <$> computeIdentity path) `catch` (\(_ :: IOException) -> pure Nothing)

computeIdentity :: FilePath -> IO String
computeIdentity rc = do
  absolute <- canonicalizePath rc
  content <- readFile absolute
  policy <- parseBoringEnvrc content
  flakeHash <- nixFlakeNarHash (dropFileName absolute) (flakeRef policy)
  pure . unlines $
    [ "direnv-nix-allow-v1",
      "envrc=" <> normalizedEnvrc policy,
      "flake=" <> flakeHash,
      "installable=" <> flakeRef policy,
      "system=default",
      "impure=false"
    ]

nixFlakeNarHash :: FilePath -> String -> IO String
nixFlakeNarHash cwd ref = do
  let args =
        [ "--extra-experimental-features",
          "nix-command flakes",
          "flake",
          "metadata",
          ref,
          "--json",
          "--no-write-lock-file"
        ]
  (code, out, err) <- readProcessWithExitCodeIn cwd "nix" args ""
  case code of
    ExitFailure _ -> ioError (userError ("nix flake metadata failed: " <> err))
    ExitSuccess -> case eitherDecodeStrict' (BS8.pack out) of
      Left problem -> ioError (userError ("could not parse nix flake metadata JSON: " <> problem))
      Right value -> case findStringKey "narHash" value of
        Just narHash -> pure narHash
        Nothing -> ioError (userError "nix flake metadata did not contain narHash")

readProcessWithExitCodeIn :: FilePath -> FilePath -> [String] -> String -> IO (ExitCode, String, String)
readProcessWithExitCodeIn cwd command args input = do
  old <- getCurrentDirectory
  Directory.setCurrentDirectory cwd
  result <- readProcessWithExitCode command args input `catch` restore old
  Directory.setCurrentDirectory old
  pure result
  where
    restore oldDir (errorValue :: IOException) = do
      Directory.setCurrentDirectory oldDir
      ioError errorValue

findStringKey :: Text.Text -> Value -> Maybe String
findStringKey key value =
  case value of
    Object object ->
      case KeyMap.lookup (AesonKey.fromText key) object of
        Just (String text) -> Just (Text.unpack text)
        Just nested -> findStringKey key nested
        Nothing -> firstJust (map (findStringKey key) (KeyMap.elems object))
    Array values -> firstJust (map (findStringKey key) (toList values))
    _ -> Nothing

firstJust :: [Maybe a] -> Maybe a
firstJust = foldr (<|>) Nothing

data BoringEnvrc = BoringEnvrc
  { normalizedEnvrc :: String,
    flakeRef :: String
  }
  deriving (Eq, Show)

parseBoringEnvrc :: String -> IO BoringEnvrc
parseBoringEnvrc content = do
  let meaningful = filter (not . null) . map normalizeLine . lines $ content
  when (null meaningful) $ ioError (userError "empty .envrc")
  let unsupported = filter (not . isAllowedLine) meaningful
  unless (null unsupported) $
    ioError (userError ("unsupported .envrc line(s): " <> intercalate "; " unsupported))
  let useFlakeLines = filter ("use flake" `isPrefixOf`) meaningful
  case useFlakeLines of
    [line] -> do
      let wordsLine = words line
      when ("--impure" `elem` wordsLine) $ ioError (userError "use flake --impure is not eligible")
      pure
        BoringEnvrc
          { normalizedEnvrc = intercalate "\n" (sort meaningful),
            flakeRef = parseFlakeRef wordsLine
          }
    [] -> ioError (userError "no use flake line found")
    _ -> ioError (userError "multiple use flake lines are not supported")

normalizeLine :: String -> String
normalizeLine = unwords . words . takeWhile (/= '#')

isAllowedLine :: String -> Bool
isAllowedLine line =
  line == "use flake"
    || "use flake " `isPrefixOf` line
    || line == "watch_file flake.nix"
    || line == "watch_file flake.lock"

parseFlakeRef :: [String] -> String
parseFlakeRef wordsLine =
  case drop 2 wordsLine of
    [] -> "."
    rest -> fromMaybe "." (find (not . ("--" `isPrefixOf`)) rest)
