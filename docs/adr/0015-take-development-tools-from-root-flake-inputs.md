---
status: accepted
---

# Take development tools from root flake inputs

The tests run on nix-unit's flake-parts module, as the devnix-labs test standard requires, and the formatter and its check come from [treefmt-nix](https://github.com/numtide/treefmt-nix), as the devnix-labs code quality standard requires. Both modules live only in their tools' flakes, so the root flake has two inputs that serve only development, `nix-unit` and `treefmt-nix`, which every consumer locks. Each input's `nixpkgs` follows the root's, so consumers gain no second nixpkgs, and every tool comes from the selected `nixpkgs`.

## Considered Options

- **An inputs flake of the `dev` partition's own.** Consumers would lock nothing extra, but the repository would keep a second lock file, unlike the other devnix-labs repos.
- **A separate `nixpkgs` input for the tools.** It would keep tool releases out of the policy's stable and unstable runs, at the cost of a second nixpkgs in consumer lock graphs.
- **A test check and formatter wrapper of this repository's own.** They need no extra input, but are custom code that the other devnix-labs repos have replaced with the modules.

## Consequences

- A consumer leaves either input out with `inputs.nixos-contracts.inputs.<input>.follows = "";`.
- nix-unit's other inputs follow nothing, and agenix-rekey's own `treefmt-nix` input follows the root's, so the lock holds one copy.
- The policy's stable and unstable runs format and lint with those revisions' tool versions, so a tool release can fail them without a change in this repository. Such a failure is fixed, or the tool configured to keep its old behavior, before the locked `nixpkgs` reaches that release.
