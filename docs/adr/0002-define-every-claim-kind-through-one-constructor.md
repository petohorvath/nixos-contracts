---
status: accepted
---

# Define every claim kind through one constructor

The set of claim kinds is open: binds, mounts and secrets are built with the same constructor, `lib.mkClaimKind`, that any project uses for a new kind, from a name, a claim type, a clash rule, a check rule and settings. The constructor resolves a service's identity once and hands it to the claim type, which derives values such as file owners from it as option defaults, then folds the claims of enabled contracts into a read-only claim set and checks every pair of entries against the clash rule and every entry against the check rule. Adapters read only claim sets, so the meaning of an identity for file ownership is written once in each kind that has files, and a new adapter cannot get it wrong.

## Considered Options

- **A closed set of kinds hardcoded in the core.** It is simpler to write, but a kind like databases or TLS certificates would then mean changing the library.
- **Each adapter resolving ownership from the service's identity**, as nixos-config's in-tree helpers (`mkAgeSecrets`, `mkPreserveAt`) do. It restates the same rule in every adapter.
- **An ownership rule passed to the constructor and applied only while folding.** It leaves the claim in the contract with a null owner and group, so a service module reading its own contract disagrees with the adapters. Option defaults on the claim type keep the two views equal.

## Consequences

- A claim already holds its final values, and a claim-set entry is the claim as its contract holds it.
- The shipped kinds have no privileged access to the core: if a shipped kind needs something the constructor cannot express, the constructor has to grow. A shipped kind imports nothing; the generic module passes it what it uses, each a value the public library exports too, and the `lint` check fails when a kind names a parent path, as it does for an adapter.
- Kinds carry no direction flag. Whether a claim offers something or requires something follows from what the kind means, and a kind that links one service to another states that relation itself.
- The claim type, the clash rule and the check rule each take one attribute set of named arguments: the kind's settings at `contracts.kinds.<kind>` and `contracts.resolve`, beside their own fields. The claim type gets the service and its resolved identity, the check rule the resolved identity and the claim-set entry, and the clash rule the two entries. Written with `...`, each keeps working when they receive further fields.
- None of them receives the top-level `config`. The shipped kinds read only their settings and resolved references, and a kind that read other options would depend on more than `contracts`, as the generic module must not. Passing `config` later would add an argument without breaking a kind; withdrawing it would break every kind that reads it.
- A check rule may return a list of reasons, so each rejected reference of one secret fails its own check.
