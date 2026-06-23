{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (IOException, try)
import Data.Aeson (eitherDecodeStrict')
import Data.ByteString.Char8 qualified as BS8
import DirenvNixAllow (
    BoringEnvrc (..),
    direnvFileHashFromBytes,
    findStringKey,
    isAllowedLine,
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
        [ labeled "minimal envrc" testMinimalEnvrc
        , labeled "watch file envrc" testWatchFileEnvrc
        , labeled "normalization" testNormalization
        , labeled "rejected envrc scenarios" testRejectedEnvrcs
        , labeled "flake ref parsing" testParseFlakeRef
        , labeled "allowed line predicate" testAllowedLines
        , labeled "direnv hash" testDirenvHash
        , labeled "narHash extraction" testNarHashExtraction
        ]

labeled :: String -> Assertion -> Test
labeled name assertion = TestLabel name (TestCase assertion)

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

testRejectedEnvrcs :: Assertion
testRejectedEnvrcs = do
    assertParseFails ""
    assertParseFails "foo\nuse flake\n"
    assertParseFails "use flake --impure\n"
    assertParseFails "use flake\nuse flake .#dev\n"
    assertParseFails "watch_file package.json\nuse flake\n"

assertParseFails :: String -> Assertion
assertParseFails input = do
    result <- try (parseBoringEnvrc input) :: IO (Either IOException BoringEnvrc)
    case result of
        Left _ -> pure ()
        Right parsed -> assertFailure ("expected parse failure, got: " <> show parsed)

testParseFlakeRef :: Assertion
testParseFlakeRef = do
    assertEqual "default ref" "." (parseFlakeRef ["use", "flake"])
    assertEqual "explicit ref" ".#dev" (parseFlakeRef ["use", "flake", ".#dev"])
    assertEqual "flag before ref" ".#dev" (parseFlakeRef ["use", "flake", "--no-write-lock-file", ".#dev"])
    assertEqual "flag after ref" ".#dev" (parseFlakeRef ["use", "flake", ".#dev", "--no-write-lock-file"])

testAllowedLines :: Assertion
testAllowedLines = do
    assertBool "use flake" (isAllowedLine "use flake")
    assertBool "use flake ref" (isAllowedLine "use flake .#dev")
    assertBool "watch flake.nix" (isAllowedLine "watch_file flake.nix")
    assertBool "watch flake.lock" (isAllowedLine "watch_file flake.lock")
    assertBool "reject arbitrary command" (not (isAllowedLine "foo"))
    assertBool "reject extra watch file" (not (isAllowedLine "watch_file package.json"))

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
