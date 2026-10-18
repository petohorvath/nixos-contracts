---
status: accepted
---

# Define every claim kind through one constructor

The set of claim kinds is open. Binds, mounts and secrets are built with the same constructor, `lib.mkClaimKind`, that any consumer uses for a new kind: a name, a claim type, an ownership rule and a clash rule. The constructor folds the claims of enabled contracts into a read-only claim set keyed by `<service>-<id>`, with each entry's owner and group already resolved from its service's identity, and checks clashes on that set: every pair of entries against the kind's clash rule, and every pair sharing a name. Adapters read only claim sets, so the meaning of an identity for file ownership is written once, and a new kind or a new adapter cannot get it wrong.

## Considered Options

A closed set of kinds hardcoded in the core is simpler to write, but a kind like databases or TLS certificates would then mean changing the library. Letting each adapter resolve ownership from the service's identity is what the in-tree materialisers do today, and it restates the same rule in every adapter.

## Consequences

The shipped kinds have no privileged access to the core: if a shipped kind needs something the constructor cannot express, the constructor has to grow. Kinds carry no direction flag. Whether a claim offers something or requires something follows from what the kind means, and a later kind that links one service to another states that relation itself.
