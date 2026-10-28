---
status: accepted
---

# Run the tests on nix-unit's flake-parts module

The nix-unit suites run on nix-unit's flake-parts module, as the devnix-labs test standard requires, instead of an `evaluation` check kept in this repo. The module lives only in nix-unit's flake, so the root gains a `nix-unit` input that serves only the tests, and the `dev` partition configures the module, which supplies the `tests.systems.<system>` output and the `nix-unit` check. The suites split into a `unit` entry point, which evaluates the generic module under a bare `lib.evalModules`, and an `integration` entry point, which evaluates NixOS configurations and the flake's outputs.

## Considered Options

- **Keep the `evaluation` check.** It needs no extra input, but it is custom test-running code that the other devnix-labs repos have replaced with the module.
- **Give the `dev` partition an inputs flake of its own for `nix-unit`.** Consumers would lock nothing extra, but the repo would keep a second lock file, unlike the other devnix-labs repos.

## Consequences

- Flake consumers lock one more input, `nix-unit`. Its `nixpkgs` follows the root's and its other inputs follow nothing, so consumers gain no second nixpkgs. A consumer drops it with `inputs.nixos-contracts.inputs.nix-unit.follows = "";`.
- The `tests` output changes shape from `tests.<system>` to `tests.systems.<system>`.
- The `nix-unit` check copies each overridden input, nixpkgs included, into a store in its build directory, and depends on the whole flake source, so any edit reruns it.
- `dev/default.nix` lists every input the suites reach, agenix-rekey's own inputs included, since the sandbox cannot fetch.

## Departures from the standard

- `dev/default.nix` names each input in `nix-unit.inputs` instead of passing `removeAttrs inputs [ "self" ]`, so the inputs the check overrides are visible in one place. A new root input therefore needs an entry there, as agenix-rekey's own inputs already do.
- The suites reach the library's NixOS modules and the backend modules as `helpers.nixos.nixosModules` and `helpers.nixos.backends`, rather than only through evaluators that import them. The adapter suites test how module lists compose, such as an adapter imported twice or a node without one, which an evaluator with fixed modules cannot express.
- The `formatting` check keeps the repository's own treefmt wrapper. Moving it to treefmt-nix, as the devnix-labs code quality standard asks, is a separate change.
