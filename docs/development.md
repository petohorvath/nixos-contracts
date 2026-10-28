# Development

The [root flake](../flake.nix) delegates the development shell, formatter, checks, and `tests` output to a `dev` flake-parts partition in [dev/](../dev/default.nix). CI runs the shared project policy.

## Shell

Run `direnv allow` at the repository root after reviewing `.envrc`, or enter the shell directly:

```sh
nix develop --no-update-lock-file
```

The shell supplies Nix, nix-unit, Git, nil, statix, and the root formatter as `treefmt`, with each program it runs, so `deadnix <file>` works on its own.

## Run checks

Run commands from the repository root, rejecting lock updates so tests use the committed dependencies:

```sh
nix fmt --no-update-lock-file
nix flake check --no-update-lock-file
```

The checks are `nix-unit`, which runs every nix-unit suite, `treefmt`, and `lint` (statix and a rule that a shipped adapter names no parent path, since it receives the public library). To run the suites of one kind, or one suite, and report each case, run the shell's nix-unit on its attribute path under `tests.systems.<system>`:

```sh
nix-unit --flake .#tests.systems.x86_64-linux.unit
nix-unit --flake .#tests.systems.x86_64-linux.unit.modules.kinds.binds
```

To run one case, select its suite and name the case with `--attr`; nix-unit treats a selected case path as a suite:

```sh
nix-unit --flake .#tests.systems.x86_64-linux.unit.modules.kinds.binds --attr testBindDefaultsToTcpOnEveryIpv4Address
```

Add `--override-input nixpkgs <flake-ref>` to run the suites against another nixpkgs.

## Formatting and lint

`nix fmt` runs treefmt as [treefmt-nix](https://github.com/numtide/treefmt-nix) configures it from [dev/treefmt.nix](../dev/treefmt.nix): nixfmt and deadnix for Nix, actionlint for the workflows, and Prettier with its default settings for Markdown, YAML and JSON, so an editor that formats on save gives the same result. `nix fmt -- <path>...` formats only the given files.

deadnix runs with `--edit`, so `nix fmt` also removes dead code; review the diff before committing.

The `treefmt` check runs the same programs on a copy of the source and fails when one changes a file or reports a finding it cannot fix; its build log shows the diff that `nix fmt` would make. statix runs in `lint` instead, since `statix fix` leaves the lints it cannot fix unreported; run `statix fix` in the shell for the ones it can.

## Test layout

The tests follow the devnix-labs test standard. Two nix-unit entry points list their suites by hand, so a suite missing from its list does not run. Each suite receives one `testContext` argument from [tests/test-context.nix](../tests/test-context.nix): nixpkgs' `lib`, the library imported from source as `contractsLib`, the [helpers](../tests/helpers/default.nix) that evaluate the modules, the [fixtures](../tests/fixtures/default.nix), which hold the evaluated examples under `examples` and the source files that suites name under `sourceFiles`, and, for the integration suites, the flake itself as `self`. The library and modules come from source, with the libnet that `flake.nix` passes them, so no suite evaluates flake-parts except through `self`.

- **Unit suites**, in [tests/unit/](../tests/unit/default.nix), evaluate the generic module with a bare `lib.evalModules`, through `helpers.contracts`. They are fast, and they fail if the core starts reading a NixOS option, which keeps the generic module usable outside NixOS. Each suite mirrors the source file it tests: `modules/mk-claim-kind.nix` maps to `tests/unit/modules/mk-claim-kind.nix`, `modules/kinds/binds.nix` to `tests/unit/modules/kinds/binds.nix`, `modules/default.nix` to `tests/unit/modules/modules.nix`, `lib/default.nix` to `tests/unit/lib.nix`, and `lib/mk-default-contract.nix` to `tests/unit/mk-default-contract.nix`. `custom-kind-example` asserts the result of the example that runs without NixOS.
- **Integration suites**, in [tests/integration/](../tests/integration/default.nix), evaluate `nixosModules.default` and the adapters in NixOS configurations, without building them, through `helpers.nixos`, which also holds the library's NixOS modules as `nixosModules` and the backend modules as `backends`, since the suites compose module lists themselves, such as an adapter imported twice. They are named after what they exercise: `nixos-module`, the three `<adapter>-adapter` suites, `nixos-examples`, which asserts the result of every NixOS [example](examples.md), and `flake-outputs`, which covers the root output shapes and checks that the flake's library, generic module, NixOS module and adapters are the code the suites import from source. The adapter suites import the real backend modules from the root flake inputs `preservation`, `agenix` and `agenix-rekey`. Consumers never evaluate these inputs, but they appear in the lock graph, where a consumer can follow them to its own copies.

Suite attribute names are the kebab-case file names, so an attribute path such as `unit.modules.mk-claim-kind` reads as the file path. Both evaluation helpers name the evaluated node `local` at default priority, so a test that is not about node identities sets none, and their `evaluateWithoutNode` evaluates a configuration without one.

[nix-unit's flake-parts module](https://github.com/nix-community/nix-unit) runs both entry points. [dev/default.nix](../dev/default.nix) passes them the flake's inputs and exposes them as the `unit` and `integration` attributes of the `tests.systems.<system>` output. The module's `nix-unit` check runs that output in the build sandbox with nix-unit from the selected `nixpkgs`. The sandbox cannot fetch, so `dev/default.nix` lists every locked input, including agenix-rekey's own inputs, in `nix-unit.inputs`, which the check passes as `--override-input`. A new input, or a new input of agenix-rekey, needs an entry there. The check copies each input into a store in its build directory, so each run first copies the nixpkgs source, and any edit to the repository reruns it.

Failure cases use nix-unit's `expectedError` and match the option path or library message, not a complete error snapshot. Clash and check cases read `contracts.failures`.

## CI and policy

The [workflow](../.github/workflows/check.yml) calls the shared [nixos-project-policy](https://github.com/petohorvath/nixos-project-policy) check. The policy also builds the checks with its stable and unstable nixpkgs pins, and treefmt-nix takes the tools from the nixpkgs in use, so a new tool release can fail those runs without a change in this repository.
