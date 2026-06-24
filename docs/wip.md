# WIP handoff

This document is a handoff for continuing `direnv-nix-allow` in an external agent.

## Project goal

`direnv-nix-allow` is a small Haskell CLI that lets direnv reuse an existing approval when two `.envrc` files are equivalent, boring, and Nix-backed.

The tool must preserve direnv's trust model:

- do not create a separate trust database;
- use direnv's own allow directory as source of truth;
- only reuse approval for a strict subset of `.envrc` files;
- never approve arbitrary shell snippets;
- reject `use flake --impure`;
- include the normalized `.envrc`, flake content identity, installable, system placeholder, and impurity flag in the identity.

## Current validation contract

`nix flake check` is the source of truth.

It should cover:

- the executable package build;
- the Cabal/HUnit test suite;
- formatting through `nix fmt`'s formatter;
- pre-commit formatting/lint checks.

Use these commands after each change:

```sh
nix fmt
nix flake check
```

`nix develop` is useful for LSP/dev tooling, but it is not required for validation. If a user interrupted `nix develop`, do not treat that as a failure.

## Current Nix design

The flake uses current upstream Haskell/iogx-adjacent inputs directly rather than the old `iogx.lib.mkFlake` API, because current `input-output-hk/iogx` does not expose `iogx.lib`.

Important files:

- `flake.nix`: flake inputs and supported systems.
- `nix/pkgs.nix`: `haskell.nix` package set and overlays.
- `nix/project.nix`: `haskell.nix` Cabal project.
- `nix/outputs.nix`: formatter, devShell, package, app, and checks.
- `nix/formatter.nix`: `nix fmt` implementation using `cabal-fmt`, `nixpkgs-fmt`, and `fourmolu`.
- `nix/shell.nix`: HLS and development shell tooling.
- `hie.yaml`: HLS cradle for library, executable, and tests.

`CHaP` and `cardano-lib` were removed intentionally. This project is not Cardano-related.

Supported systems:

- `x86_64-linux`
- `aarch64-linux`

Local `nix flake check` on x86 should not force-build ARM derivations. ARM coverage is handled by GitHub Actions matrix jobs.

## Current Haskell design

Core logic lives in `src/DirenvNixAllow.hs` and the CLI shim lives in `src/Main.hs`.

The parser accepts only boring `.envrc` lines:

- `use flake`
- `use flake <ref>`
- `watch_file flake.nix`
- `watch_file flake.lock`

Important parser detail: flake fragments such as `.#dev` and `.#ci` contain `#`, so comment stripping must not blindly cut at every `#`. A `#` starts a comment only when it appears at the start of a line or after whitespace.

The test suite in `tests/Spec.hs` covers:

- minimal envrc parsing;
- `watch_file` parsing and normalization;
- whitespace/comment normalization;
- rejected envrc scenarios;
- flake ref parsing;
- allowed-line predicates;
- direnv allow hash behavior;
- `narHash` extraction from Nix metadata JSON.

## Recent failure fixed

`nix flake check` failed in the HUnit suite because `normalizeLine` previously used `takeWhile (/= '#')`, which truncated flake refs:

- expected `.#ci`, got `.`;
- expected `use flake .#dev`, got `use flake .`.

The intended fix is to preserve `#` inside tokens and strip only shell-style comments that start at line start or after whitespace.

## Known non-fatal warnings

These may appear and are not necessarily blockers:

- `app 'apps.x86_64-linux.default' lacks attribute 'meta'`;
- `evaluation warning: 'system' has been renamed to/replaced by 'stdenv.hostPlatform.system'`;
- transient SQLite database busy messages from the Nix store.

## Known generated files

`nix develop` may generate `.pre-commit-config.yaml`. It is intentionally ignored in `.gitignore`.

If a stale pre-commit hook complains that `.pre-commit-config.yaml` is missing, either run:

```sh
PRE_COMMIT_ALLOW_NO_CONFIG=1 git commit ...
```

or uninstall/reinstall the hook from the current shell. Do not commit `.pre-commit-config.yaml` unless the project policy changes.

## Next recommended steps

1. Pull latest `main`.
2. Run `nix fmt`.
3. Run `nix flake check`.
4. If formatting changes files, commit them with `Run nix fmt`.
5. If `nix flake check` fails, inspect the exact failing derivation log with `nix log <drv>`.

Potential future improvements:

- add `meta` to app/package outputs if the warning becomes annoying;
- replace `system=default` with an actual evaluated Nix system identity;
- split installable refs from flake source refs before calling `nix flake metadata` so `.#devShell`-style installables do not confuse metadata lookup;
- improve Bash hook compatibility with upstream direnv's full Bash hook behavior.
