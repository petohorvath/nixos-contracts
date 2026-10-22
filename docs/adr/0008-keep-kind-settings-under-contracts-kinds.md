---
status: accepted
---

# Keep kind settings under `contracts.kinds`

A claim kind's settings sit at `contracts.kinds.<kind>`, such as `contracts.kinds.mounts.classes` and `contracts.kinds.secrets.location`, not at `contracts.<kind>`. At the root, a kind's settings shared one namespace with the library's own options, `services`, `claimSets`, `assertions`, `failures` and `adapters`, so `lib.mkClaimKind` kept a list of reserved names in step with the root by hand, and every option the library added to the root would break a project's kind of that name. Under `kinds`, the root belongs to the library, and a kind may take any name but the contract's own fields `enable` and `identity`, beside which its claims sit. `kinds` matches how adapters keep their settings, under `contracts.adapters.<adapter>`, and tells apart the paths that looked alike at the root: `contracts.secrets` for the settings, `contracts.claimSets.secrets` for the claim set and a contract's `secrets` for its claims.

## Considered Options

Each kind's claim set inside its settings, as `contracts.kinds.<kind>.claimSet`, would gather a kind in one place, but mixes a read-only set with writable settings, reserves a name in every kind's settings, and lengthens the path adapters read most. A contract's claims under `contracts.services.<service>.claims.<kind>` would free `enable` and `identity` too, at the cost of a longer path in every service module, for two names that stay stable while a contract has no other fields. `claimKinds` repeats the glossary term but reads close to `claimSets`, and `settings` does not say whose settings it holds, while adapters keep theirs elsewhere.

## Consequences

Every path a node or adapter writes for a shipped kind moves, such as `contracts.mounts.classes` to `contracts.kinds.mounts.classes` and `contracts.secrets.location` to `contracts.kinds.secrets.location`, and a project's kind declares and reads its settings under `contracts.kinds.<name>`. The decisions of earlier ADRs stand; ADR-0006 still names the generators at their former path, `contracts.secrets.generators`, which is now `contracts.kinds.secrets.generators`. The library may add options to the `contracts` root without breaking a project's kind.
