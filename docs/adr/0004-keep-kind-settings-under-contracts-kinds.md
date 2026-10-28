---
status: accepted
---

# Keep kind settings under `contracts.kinds`

A claim kind's settings sit at `contracts.kinds.<kind>`, such as `contracts.kinds.mounts.classes`, not at `contracts.<kind>`, so the `contracts` root belongs to the library and a kind may take any name but the contract's own fields `enable` and `identity`, beside which its claims sit. At the root, a kind's settings would share one namespace with the library's own options, such as `services`, `claimSets`, `node` and `resolve`, so `lib.mkClaimKind` would keep a list of reserved names in step with the root by hand, and every option the library added would break a project's kind of that name.

## Considered Options

- **Each kind's claim set inside its settings, as `contracts.kinds.<kind>.claimSet`.** It gathers a kind in one place, but mixes a read-only set with writable settings, reserves a name in every kind's settings, and lengthens the path adapters read most.
- **A contract's claims under `contracts.services.<service>.claims.<kind>`.** It frees `enable` and `identity` too, at the cost of a longer path in every service module, for two names that stay stable while a contract has no other fields.
- **`claimKinds` or `settings` as the name.** `claimKinds` repeats the glossary term but reads close to `claimSets`, and `settings` does not say whose settings it holds, while adapters keep theirs elsewhere.

## Consequences

- The library adds options to the `contracts` root without breaking a project's kind, and a project's kind declares and reads its settings under `contracts.kinds.<name>`.
- `kinds` matches how adapters keep their settings, under `contracts.adapters.<adapter>`, and tells apart paths that would look alike at the root: `contracts.kinds.secrets` for the settings, `contracts.claimSets.secrets` for the claim set and a contract's `secrets` for its claims.
