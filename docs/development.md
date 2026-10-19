# Development

The [root flake](../flake.nix) delegates the development shell, formatter, and checks to a `dev` flake-parts partition in [dev/](../dev/default.nix). CI runs the shared project policy.

## Shell

Run `direnv allow` at the repository root after reviewing `.envrc`, or enter the shell directly:

```sh
nix develop --no-update-lock-file
```

The shell supplies Nix, nil, nixfmt, statix, deadnix, Git, shfmt, Prettier, actionlint, and the root formatter.

## Run checks

Run commands from the repository root, rejecting lock updates so tests use the committed dependencies:

```sh
nix fmt --no-update-lock-file
nix flake check --no-update-lock-file
```

The checks are `evaluation` (the nix-unit suite), `formatting`, `lint` (statix and deadnix), and `workflows` (actionlint). To run the suite, or one suite within it, and report each case:

```sh
nix run --inputs-from . nixpkgs#nix-unit -- --flake .#tests.x86_64-linux
nix run --inputs-from . nixpkgs#nix-unit -- --flake .#tests.x86_64-linux.modules.kinds.binds
```

## Test layout

Test files mirror source paths: `modules/mk-claim-kind.nix` maps to `tests/modules/mk-claim-kind.nix`, `modules/kinds/binds.nix` to `tests/modules/kinds/binds.nix`, and `nixos/default.nix` to `tests/nixos/default.nix`. `tests/flake.nix` covers the root output shapes, and `tests/integration/examples.nix` asserts the result of every [example](examples.md). [tests/evaluation.nix](../tests/evaluation.nix) nests the suites into the `tests.<system>` output.

Tests come in two layers:

- **Core tests** evaluate the generic module with a bare `lib.evalModules`, through [tests/fixtures/contracts.nix](../tests/fixtures/contracts.nix). They are fast, and they fail if the core starts reading a NixOS option, which keeps the generic module usable outside NixOS.
- **NixOS tests** evaluate `nixosModules.default` and the adapters in NixOS configurations, without building them, through [tests/fixtures/nixos.nix](../tests/fixtures/nixos.nix). The adapter tests import the real backend modules from the root flake inputs `preservation`, `agenix` and `agenix-rekey`. Consumers never evaluate these inputs, but they appear in the lock graph, where a consumer can follow them to its own copies.

The `evaluation` check runs nix-unit in the build sandbox, which cannot fetch, so [dev/checks.nix](../dev/checks.nix) passes every locked input, including agenix-rekey's own inputs, with `--override-input`. A new input, or a new input of agenix-rekey, needs an entry there.

Failure cases use nix-unit's `expectedError` and match the option path or library message, not a complete error snapshot. Clash cases read the failed messages of `contracts.assertions`.

## CI and policy

The [workflow](../.github/workflows/check.yml) calls the shared [nixos-project-policy](https://github.com/petohorvath/nixos-project-policy) check.
