# Contributing

Follow the local [development guide](docs/development.md).

## Changes and review

Work on a branch and open a PR with a Conventional Commit title, such as `feat: Add the preservation adapter`. Describe the resulting behavior, compatibility effects, and validation. Mark breaking changes with `!` and add migration notes to the [changelog](CHANGELOG.md).

Run `nix fmt --no-update-lock-file` and `nix flake check --no-update-lock-file`. Add tests at public interfaces for behavior changes. Use the terms of [GLOSSARY.md](GLOSSARY.md) in code, tests and documentation, and record decisions that are hard to reverse in `docs/adr/`.

## Public interface

The public interface comprises `nixosModules.default`, the adapter modules `nixosModules.{preservation,agenix-rekey,systemd-credentials}`, `nixosModules.cross-config`, `modules.generic.default`, the `contracts.*` options the [API reference](docs/api.md) describes, and `lib.mkDefaultContract`, `lib.mkClaimKind`, `lib.types.reference`, `lib.types.referenceTo` and `lib.types.tag`. Keep `lib/` loadable by path with a caller-owned library, and the `modules/` and `nixos/` directories by path when applied to `{ libnet }`.

## Releases

Release with Semantic Versioning tags and [CHANGELOG.md](CHANGELOG.md). During 0.x, breaking changes require a minor bump.

## License

Original code uses the [MIT license](LICENSE).
