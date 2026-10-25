---
status: superseded in part by ADR-0014 and ADR-0015
---

# Define every claim kind through one constructor

The set of claim kinds is open. Binds, mounts and secrets are built with the same constructor, `lib.mkClaimKind`, that any consumer uses for a new kind: a name, a claim type, a clash rule and a check rule. The constructor resolves a service's identity in one place and hands it to the kind's claim type, which derives values such as file owners from it as option defaults, so a claim already holds its final values. The constructor folds the claims of enabled contracts into a read-only claim set keyed by `<service>-<id>`, each entry the claim as its contract holds it, and checks that set: every pair of entries against the kind's clash rule, every pair sharing a name, and every entry against the kind's check rule. Adapters read only claim sets, so the meaning of an identity for file ownership is written once in each kind that has files, and a new adapter cannot get it wrong.

## Considered Options

A closed set of kinds hardcoded in the core is simpler to write, but a kind like databases or TLS certificates would then mean changing the library. Letting each adapter resolve ownership from the service's identity is what nixos-config's in-tree helpers (`mkAgeSecrets`, `mkPreserveAt`) do today, and it restates the same rule in every adapter. An ownership rule passed to the constructor and applied only while folding left the claim in the contract with a null owner and group, so a service module reading its own contract disagreed with the adapters; option defaults on the claim type keep the two views equal.

## Consequences

The shipped kinds have no privileged access to the core: if a shipped kind needs something the constructor cannot express, the constructor has to grow. Kinds carry no direction flag. Whether a claim offers something or requires something follows from what the kind means, and a later kind that links one service to another states that relation itself.
