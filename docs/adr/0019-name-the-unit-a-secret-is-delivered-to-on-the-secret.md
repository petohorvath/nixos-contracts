---
status: accepted
---

# Name the unit a secret is delivered to on the secret

A secret names the unit it is delivered to in a writable `unit`, which defaults to a dynamic identity's unit and is null for a static identity. A secret is delivered when its `unit` is not null, whichever adapters are imported, and a check fails for a delivered secret while no delivery adapter is imported. Before, the identity decided: a secret was delivered when its identity was dynamic and a delivery adapter was imported. A static identity could not get delivery, so every unit of its account could read its secrets, and a dynamic identity could not keep one secret on the backend's location for its `sharedGroup`.

Neither the identity nor the contract can hold the unit. A static identity is an account, and one account runs several units of one service: nixpkgs' `mastodon` account runs `mastodon-init-dirs`, `mastodon-init-db`, `mastodon-web`, the sidekiq units and a configurable number of streaming units, of which only `mastodon-init-dirs.service` reads the secret files. One contract covers all of them, which ADR-0009 leaves implicit: it gives a helper with its own process a contract of its own, not every unit of a service. A delivered secret's `path`, `/run/credentials/<unit>/<name>`, differs per unit, and a daemon's option takes one path, so a secret is delivered to at most one unit. A dynamic identity's user is allocated for exactly one unit, so a check fails for its secret delivered to another.

## Considered Options

- **A unit on the static identity.** It mirrors `dynamic.unit`. However, the account it describes runs several units, and the identity would still deliver every secret or none.
- **A unit on the contract, and a `delivered` flag on each secret.** No secret could name the wrong unit. However, a contract covers several units, such as Mastodon's, so the contract's one unit would be wrong for some of its secrets.
- **A list of units on the secret.** One claim would serve several units. However, its `path` differs per unit, so a daemon's option could not take it. Two units that each need a delivered copy hold two claims, the second `copied` from the first.
- **A unit derived for a static identity**, such as `<service>.service`, or the units that run as the account. `path` depends on the unit, so the unit cannot be found from where `path` is used. The units of an account are ambiguous, and `<service>.service` is wrong for chrony, Mastodon and Nextcloud, where a guess that names another existing unit fails only at runtime.
- **Delivery that follows the delivery adapter**, as before. Importing an adapter would keep changing what a contract means, and a missing adapter would move a secret silently instead of failing a check.

## Consequences

- The module that hands a secret's `path` to the daemon names the unit that reads it, such as `secrets.secret-key.unit = "grafana.service";`. A node overrides it like any other field.
- A dynamic identity's secret read through its `sharedGroup` sets `unit = null`. Without a delivery adapter, a dynamic identity's secret fails a check otherwise.
- A delivered secret's `group` defaults to `root`, since only the delivery adapter reads the installed file, so the account's other units cannot read it.
- The systemd-credentials adapter delivers into any unit a secret names, requires each to be a service with a command, and requires `DynamicUser` only for the units of dynamic identities.
- `secrets.<id>.unit` is a fact of the claim, not a copy of the identity, so it stays when the resolved identity is exposed on the contract.
