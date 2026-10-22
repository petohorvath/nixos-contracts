# Agent instructions

## Development and review

Before implementation, read [CONTRIBUTING.md](CONTRIBUTING.md) and the [development guide](docs/development.md). Use the root shell, formatter, and checks with the committed lock. Keep the generic module free of NixOS options, so its tests keep running under a bare `lib.evalModules`. Leave merge and release approval to a human.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `petohorvath/nixos-contracts`, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels, each named after its role: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: root `GLOSSARY.md` and `docs/adr/`. Before exploring the codebase, read `docs/agents/domain.md`.
