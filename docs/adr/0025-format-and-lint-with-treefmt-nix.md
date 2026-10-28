---
status: accepted
---

# Format and lint with treefmt-nix

The repository formats and lints its code as the devnix-labs code quality standard describes: one [treefmt-nix](https://github.com/numtide/treefmt-nix) configuration in `dev/treefmt.nix` supplies the root formatter, the `treefmt` check and the development shell's tools. The root gains a `treefmt-nix` input for its flake-parts module, which, like the `nix-unit` input of [ADR-0024](0024-run-the-tests-on-nix-units-flake-parts-module.md), serves only development.

## Decisions

- **One configuration.** `dev/treefmt.nix` enables nixfmt, deadnix, actionlint and Prettier. Prettier runs with its defaults and no `.prettierrc.json`, so editors that format on save agree with `nix fmt`. treefmt-nix generates the formatter, the check and the shell's tools from it, replacing the `contracts-fmt` wrapper, `dev/treefmt.toml` and the hand-written `formatting` check.
- **A `treefmt` check.** It replaces the `formatting` check. It runs every enabled program on the flake source and fails when one would change a file or reports a finding it cannot fix.
- **statix and the adapter guard in `lint`.** treefmt-nix would run `statix fix`, which passes lints that it cannot fix, so `lint` runs `statix check` instead. The rule that a shipped adapter names no parent path stays in `lint`, since it guards the repository's own files. deadnix and actionlint move from `lint` to treefmt.
- **A `treefmt-nix` root input.** Its `nixpkgs` follows the root one, so every program comes from the selected `nixpkgs`. nix-unit's own `treefmt-nix` input still follows nothing.
- **No shfmt.** It formatted only `.envrc`.

## Consequences

- Consumer lock graphs gain the treefmt-nix source, but no second nixpkgs. A consumer leaves it out with `inputs.nixos-contracts.inputs.treefmt-nix.follows = "";`.
- `checks.<system>.formatting` becomes `checks.<system>.treefmt`.
- `nix-unit.inputs` in `dev/default.nix` names the new input, as ADR-0024 requires of every root input.
- The policy's stable and unstable runs format and lint with those revisions' tool versions, so a tool release can fail them without a change in this repository. Such a failure is fixed, or the tool configured to keep its old behavior, before the locked `nixpkgs` reaches that release.

## Considered Options

- **Keep the hand-written wrapper and `treefmt.toml`.** It needed a wrapper, a TOML file and a check that treefmt-nix generates, and it differed from the other devnix-labs repos.
- **A separate `nixpkgs` input for the tools.** It would keep tool releases out of the stable and unstable runs, at the cost of a second nixpkgs in consumer lock graphs.
