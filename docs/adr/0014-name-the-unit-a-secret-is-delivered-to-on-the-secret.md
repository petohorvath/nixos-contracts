---
status: accepted
---

# Name the unit a secret is delivered to on the secret

A secret names the unit it is delivered to in a writable `unit`, which defaults to a dynamic identity's unit and is null for a static identity, and is delivered when its `unit` is not null, whichever adapters are imported. Neither the identity nor the contract can hold the unit: one account runs several units of one service, and a delivered secret's `path`, `/run/credentials/<unit>/<name>`, differs per unit, while a daemon's option takes one path, so a secret is delivered to at most one unit. A static identity's secret can then be delivered, so the account's other units cannot read it, and a dynamic identity can keep one secret where the backend installs it, for its `sharedGroup`.

## Considered Options

- **A unit on the static identity.** It mirrors `dynamic.unit`, but the account it describes runs several units: nixpkgs' `mastodon` account runs `mastodon-init-dirs`, `mastodon-init-db`, `mastodon-web`, the sidekiq units and a configurable number of streaming units, of which only `mastodon-init-dirs.service` reads the secret files. The identity would still deliver every secret or none.
- **A unit on the contract, and a `delivered` flag on each secret.** No secret could name the wrong unit, but one contract covers all of a service's units, such as Mastodon's, since [ADR-0003](0003-hold-a-claim-on-the-contract-of-the-process-that-reads-it.md) gives a helper with its own process a contract of its own, not every unit. The contract's one unit would be wrong for some of its secrets.
- **A list of units on the secret.** One claim would serve several units, but its `path` differs per unit, so a daemon's option could not take it. Two units that each need a delivered copy hold two claims, the second `copied` from the first.
- **A unit derived for a static identity**, such as `<service>.service`, or the units that run as the account. `path` depends on the unit, so the unit cannot be found from where `path` is used. The units of an account are ambiguous, and `<service>.service` is wrong for chrony, Mastodon and Nextcloud, where a guess that names another existing unit fails only at runtime.
- **Delivery that follows the identity and the delivery adapter**: a secret delivered when its identity is dynamic and a delivery adapter is imported. A static identity could not get delivery, importing an adapter would change what a contract means, and a missing adapter would move a secret silently instead of failing a check.

## Consequences

- The module that hands a secret's `path` to the daemon names the unit that reads it, such as `secrets.secret-key.unit = "grafana.service";`. A node overrides it like any other field.
- A check fails for a delivered secret while no delivery adapter is imported. A dynamic identity's user is allocated for exactly one unit, so a check also fails for its secret delivered to another.
- A dynamic identity's secret read through its `sharedGroup` sets `unit = null`. Without a delivery adapter, a dynamic identity's secret fails a check otherwise.
- A delivered secret's `group` defaults to `root`, since only the delivery adapter reads the installed file, so the account's other units cannot read it.
- The systemd-credentials adapter delivers into any unit a secret names, requires each to be a service with a command, and requires `DynamicUser` only for the units of dynamic identities.
- `secrets.<id>.unit` is a fact of the claim, not a copy of the identity, so it stays if the resolved identity is ever exposed on the contract.
