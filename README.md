# direnv-nix-allow

Nix-aware direnv approval reuse without weakening direnv's path-specific trust model.

`direnv-nix-allow` is a companion tool for [`direnv`](https://direnv.net/) that recognizes equivalent boring Nix-backed `.envrc` files and materializes normal `direnv allow` approvals before direnv blocks them.

The core idea is deliberately narrow:

- direnv remains the source of approval truth.
- This tool does not maintain a second trust database.
- Only boring Nix `.envrc` files are eligible.
- Equivalent Nix source identities can reuse an existing direnv approval at another path.

## Intended effects

- Reuse approval across Git worktrees.
- Reuse approval across moved checkouts.
- Avoid repeated approval for equivalent Nix-backed project environments.
- Preserve manual approval for arbitrary `.envrc` Bash.

## Install

With Nix:

```sh
nix profile install github:klarkc/direnv-nix-allow
```

Then replace the normal direnv hook:

```sh
# before
# eval "$(direnv hook bash)"

# after
eval "$(direnv-nix-allow hook bash)"
```

## Commands

```sh
direnv-nix-allow hook bash
```

Prints a Bash hook that runs `direnv-nix-allow materialize --quiet` before `direnv export bash`.

```sh
direnv-nix-allow materialize
```

If the current `.envrc` is an unapproved boring Nix `.envrc`, search direnv's existing allow store for another currently allowed `.envrc` with the same Nix identity. When a match is found, run `direnv allow` for the current path.

```sh
direnv-nix-allow identity
```

Print the computed identity for the current boring Nix `.envrc`.

## Boring `.envrc` policy

The first version accepts only small, reviewable Nix delegators, such as:

```sh
use flake
```

or:

```sh
watch_file flake.nix
watch_file flake.lock
use flake . --no-write-lock-file
```

It rejects arbitrary shell, `source`, `source_env`, `dotenv`, `--impure`, and other unsupported commands.

## Development

```sh
nix develop
cabal build
nix flake check
```
