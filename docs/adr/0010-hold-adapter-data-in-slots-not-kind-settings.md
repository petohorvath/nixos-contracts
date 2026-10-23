---
status: accepted
---

# Hold adapter data in slots, not kind settings

The data an adapter gives a claim kind sits in a slot: one option under `contracts.kinds.<kind>`, null while no such adapter is imported, holding the adapter's data as one submodule that takes one definition. The secrets kind has two, `backend`, with the backend's `location` and `generators`, and `delivery`, with the delivered `path`. A slot is not a setting: a node writes a kind's settings, such as `contracts.kinds.mounts.classes`, while an adapter fills a slot and a node does not. Before, the backend adapter set `location` and `generators` as two options and the delivery adapter set `delivery`, beside the settings and typed alike, so nothing in the API told them apart. Each option took one definition, so a second backend failed, but `location` and `generators` could still come from two modules, and the check compared a secret's `generate` with generators of a backend that did not install it. In one slot, the backend's data comes from one definition, and null says that no adapter is imported, in place of a `location` default that fails and a null generator list.

## Considered Options

The three options, each taking one definition, kept a node's way to replace one of them with `lib.mkForce`, but could not tie `location` to `generators`. Slots at `contracts.adapters.<adapter>` would sit beside the adapters' own settings, but the kind would then name the adapters it reads, while any backend adapter fills `backend`, and the check rule of `lib.mkClaimKind` receives only `contracts.kinds.<kind>` (ADR-0006), so the generators must sit there for the check to read them. A name field in each slot would let messages name the imported adapter, but messages say "the secret backend" and list its generators instead, and the module system already names both files when a second adapter defines a slot.

## Consequences

Adapters, and any module that reads or sets `contracts.kinds.secrets.location`, `generators` or `delivery`, move to the slots; service modules do not change. A node that replaces part of a slot, such as the backend's location, replaces the whole slot with `lib.mkForce`, generators included. The slot type keeps its message through the module system's submodule substitution, which `types.unique` loses in nixpkgs. The paths ADR-0008 names, `contracts.kinds.secrets.location` and `contracts.kinds.secrets.generators`, are now `contracts.kinds.secrets.backend.location` and `contracts.kinds.secrets.backend.generators`; its decision stands. `lib.mkClaimKind` still declares a kind's slots with its settings and hands both to the check rule as `settings`.
