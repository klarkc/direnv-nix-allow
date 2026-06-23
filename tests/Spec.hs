{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Aeson (eitherDecodeStrict')
import Data.ByteString.Char8 qualified as BS8
import DirenvNixAllow
  ( BoringEnvrc (..),
    direnvFileHashFromBytes,
    findStringKey,
    normalizeLine,
    parseBoringEnvrc,
    parseFlakeRef,
  )
import Test.HUnit

main :: IO ()
main = do
  counts <- runTestTT tests
  if errors counts + failures counts == 0
    then pure ()
    else fail "test failures"

tests :: Test
tests =
  TestList
    [ TestLabel "minimal envrc" testMinimalEnvrc,
      TestLabel "watch file envrc" testWatchFileEnvrc,
      TestLabel "normalization" testNormalization,
      TestLabel "flake ref parsing" testParseFlakeRef,
      TestLabel "direnv hash" testDirenvHash,
      TestLabel "narHash extraction" testNarHashExtraction
    ]

testMinimalEnvrc :: Assertion
testMinimalEnvrc = do
  parsed <- parseBoringEnvrc "use flake\n"
  assertEqual "minimal envrc" (BoringEnvrc "use flake" ".") parsed

testWatchFileEnvrc :: Assertion
testWatchFileEnvrc = do
  parsed <- parseBoringEnvrc "watch_file flake.nix\nwatch_file flake.lock\nuse flake .#ci --no-write-lock-file\n"
  assertEqual "ref" ".#ci" (flakeRef parsed)
  assertEqual
    "normalized sorted lines"
    "use flake .#ci --no-write-lock-file\nwatch_file flake.lock\nwatch_file flake.nix"
    (normalizedEnvrc parsed)

testNormalization :: Assertion
testNormalization = do
  assertEqual "comments removed" "use flake .#dev" (normalizeLine "  use    flake   .#dev   # comment")
  parsed <- parseBoringEnvrc "\n  # comment\n  use    flake   .#dev   # comment\n"
  assertEqual "normalized envrc" "use flake .#dev" (normalizedEnvrc parsed)
  assertEqual "flake ref" ".#dev" (flakeRef parsed)

testParseFlakeRef :: Assertion
testParseFlakeRef = do
  assertEqual "default ref" "." (parseFlakeRef ["use", "flake"])
  assertEqual "explicit ref" ".#dev" (parseFlakeRef ["use", "flake", ".#dev"])
  assertEqual "flag before ref" ".#dev" (parseFlakeRef ["use", "flake", "--no-write-lock-file", ".#dev"])
  assertEqual "flag after ref" ".#dev" (parseFlakeRef ["use", "flake", ".#dev", "--no-write-lock-file"])

testDirenvHash :: Assertion
testDirenvHash = do
  let content = BS8.pack "use flake\n"
      pathA = "/tmp/a/.envrc"
      pathB = "/tmp/b/.envrc"
      hashA1 = direnvFileHashFromBytes pathA content
      hashA2 = direnvFileHashFromBytes pathA content
      hashB = direnvFileHashFromBytes pathB content
      hashChanged = direnvFileHashFromBytes pathA (BS8.pack "use flake .#dev\n")
  assertEqual "deterministic" hashA1 hashA2
  assertBool "path-sensitive" (hashA1 /= hashB)
  assertBool "content-sensitive" (hashA1 /= hashChanged)
  assertEqual "sha256 hex length" 64 (length hashA1)

testNarHashExtraction :: Assertion
testNarHashExtraction = do
  value <- case eitherDecodeStrict' "{\"resolved\":{\"narHash\":\"sha256-example\"}}" of
    Left err -> assertFailure err
    Right parsed -> pure parsed
  assertEqual "narHash" (Just "sha256-example") (findStringKey "narHash" value)
  assertEqual "missing key" Nothing (findStringKey "missing" value)
