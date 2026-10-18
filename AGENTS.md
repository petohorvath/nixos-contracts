# Agent instructions

## Development and review

Before implementation, read [CONTRIBUTING.md](CONTRIBUTING.md) and the [development guide](docs/development.md). Use the root shell, formatter, and checks with the committed lock. Keep the generic module free of NixOS options, so its tests keep running under a bare `lib.evalModules`. Leave merge and release approval to a human.

## Domain docs

Single-context layout: root `GLOSSARY.md` and `docs/adr/`. Before exploring the codebase, read `docs/agents/domain.md`.
