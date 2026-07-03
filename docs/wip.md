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

Fixed in commits `e60ab00` and `3040dfe`. The `normalizeLine` function no longer uses `takeWhile (/= '#')`; it preserves `#` inside tokens and strips only shell-style comments that start at line start or after whitespace.

Validation: `nix flake check` exits 0 on `main` as of 2026-07-02, with only expected non-fatal warnings.

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

## Validation record

- **2026-07-02**: `nix fmt` → no changes. `nix flake check` → exit 0; running checks passed, and package/app/devShell/formatter outputs evaluated successfully. Only expected non-fatal warnings.

## Design decision: external interface preference

Prefer external interfaces in this order when they are available, stable, and cheap enough:

1. CLI interface;
2. code/API interface;
3. direct file interface.

This is a preference, not an absolute rule. Use direct file access when the file is the documented source of truth or there is no adequate CLI/API. In this project that means:

- keep using the `nix` CLI for Nix facts and behavior, because the CLI is the user-visible contract shared with direnv workflows;
- keep using the `direnv` CLI to materialize approval (`direnv allow <path>`), so direnv remains the authority for writes;
- keep reading direnv allow files for discovery, because the current implementation needs to enumerate already allowed `.envrc` paths and there is no known `direnv` CLI that exposes this exact list as a stable query.

No broad refactor is needed for this rule. Existing Nix and direnv write paths already follow it; only the `system=default` identity placeholder should be replaced.

## Next implementation decision: real Nix system identity

Replace the identity line:

```text
system=default
```

with the configured Nix system from the Nix CLI:

```sh
nix config show system
```

Local evidence: with Determinate Nix 3.8.6 / Nix 2.30.2 this prints `x86_64-linux` without `--impure`.

Implementation guidance for Build:

- add a small helper that runs `nix config show system`, trims the output, rejects an empty value, and fails closed on command failure;
- call that helper from `computeIdentity` and emit `system=<value>` instead of `system=default`;
- do not use `nix eval --impure --expr builtins.currentSystem`;
- keep using `nix flake metadata` for the flake content hash for now;
- add/adjust tests around identity construction/system handling. If needed, factor identity rendering into a pure helper so tests do not need to invoke `nix`;
- validate with `nix fmt` and `nix flake check`.

## Completed handoff: `AGENTS.md`

Repository `AGENTS.md` was created in commit `05d9403`. It is now the concise agent-facing guide for this repository and links back here for detailed context.

## Dotfiles handoff: install and enable `direnv-nix-allow`

User requested a handoff for another agent implementing `direnv-nix-allow` in the user's dotfiles.

Goal for the dotfiles agent:

- make the `direnv-nix-allow` executable available in interactive shells;
- wire the Bash hook so `direnv-nix-allow materialize --quiet` runs before `direnv export bash`;
- preserve direnv as the authority for trust writes (`direnv allow` remains the only write path);
- avoid adding any separate trust database, auto-allow policy, or broad `.envrc` approval logic in dotfiles.

Recommended implementation shape:

1. Add this repository as a dotfiles flake input or otherwise expose its `packages.<system>.default` output in the user's package set.
2. Add the package to the user's interactive shell environment so `command -v direnv-nix-allow` succeeds.
3. For Bash, replace the normal direnv Bash hook with this tool's wrapper:

   ```sh
   eval "$(direnv-nix-allow hook bash)"
   ```

   Do not also install `eval "$(direnv hook bash)"` in the same shell, because the wrapper already calls `direnv export bash`.
4. Keep normal `direnv` installed/enabled. This tool depends on the `direnv` CLI for materializing approval and on the `nix` CLI for identity facts.
5. If the user's dotfiles primarily target a non-Bash shell, pause and design shell-specific behavior first. This repository currently exposes only `hook bash`.

Acceptance criteria for dotfiles integration:

- A new interactive Bash shell has both `direnv` and `direnv-nix-allow` on `PATH`.
- `direnv-nix-allow help` prints usage.
- `direnv-nix-allow hook bash` prints a hook that defines `_direnv_nix_allow_hook` and calls `direnv export bash`.
- There is no duplicate plain `direnv hook bash` installation in Bash startup files.
- In a boring Nix-backed project, `direnv-nix-allow identity` prints an identity; in a non-boring `.envrc`, it fails closed rather than approving anything.
- Existing manually approved direnv workflows continue to work unchanged.

Risks / edge cases for the dotfiles agent:

- Hook ordering matters: the wrapper should run where the normal direnv Bash hook would have run.
- The current identity still emits `system=default` until the next implementation target below is completed; dotfiles integration should not paper over that in shell code.
- Avoid enabling this for shells that are not supported by the repository hook unless a shell-specific hook is implemented here first.
- Do not read or mutate direnv allow files from dotfiles; this repository handles that internally.

Potential future improvements:

- add `meta` to app/package outputs if the warning becomes annoying;
- split installable refs from flake source refs before calling `nix flake metadata` so `.#devShell`-style installables do not confuse metadata lookup;
- improve Bash hook compatibility with upstream direnv's full Bash hook behavior.
