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

## Build handoff: create `AGENTS.md`

User requested Build write a repository `AGENTS.md`.

Suggested content:

- concise project summary: small Haskell CLI that reuses existing direnv approval only for equivalent, boring, Nix-backed `.envrc` files;
- validation contract: run `nix fmt` and `nix flake check`; `nix flake check` is the source of truth;
- architecture map: `src/DirenvNixAllow.hs`, `src/Main.hs`, `tests/Spec.hs`, and the key `nix/*.nix` files listed above;
- trust/security rules: no separate trust database, direnv allow dir is source of truth, reject arbitrary shell snippets and `use flake --impure`, identity must include normalized `.envrc`, flake content hash, installable, system, and impurity flag;
- external interface preference: prefer CLI interfaces over code/API interfaces over direct file interfaces when available, stable, and cheap enough; this is a preference, not an absolute rule;
- current justified file-interface exception: reading direnv allow files to enumerate already allowed `.envrc` paths, because no known stable `direnv` CLI exposes that exact list;
- known warnings: missing app `meta`, `system` rename warning, transient Nix store/cache messages, and local `aarch64-linux` omission are non-fatal unless behavior changes;
- next implementation target: replace `system=default` with `nix config show system` as described above, with fail-closed behavior and no `--impure`.

Keep `AGENTS.md` practical and short. Do not duplicate all of `docs/wip.md`; link or point to it for detailed handoff context.

Potential future improvements:

- add `meta` to app/package outputs if the warning becomes annoying;
- split installable refs from flake source refs before calling `nix flake metadata` so `.#devShell`-style installables do not confuse metadata lookup;
- improve Bash hook compatibility with upstream direnv's full Bash hook behavior.
