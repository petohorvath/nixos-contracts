---
status: accepted
---

# Hold adapter data in slots, not kind settings

The data an adapter gives a claim kind sits in a slot: one option under `contracts.kinds.<kind>`, null while no such adapter is imported, holding the adapter's data as one submodule that takes one definition, such as the secrets kind's `backend`, with the backend's `path` and `generators`, and `delivery`, with the delivered `path`. A slot is not a setting: a node writes a kind's settings, such as `contracts.kinds.mounts.classes`, while an adapter fills a slot and a node does not.

## Considered Options

- **One option per datum, each taking one definition, beside the settings.** A node could replace one of them with `lib.mkForce`, but nothing in the API tells them from settings, `path` and `generators` could come from two modules, and a check could compare a secret's generator with the generators of a backend that does not install it.
- **Slots at `contracts.adapters.<adapter>`**, beside the adapters' own settings. The kind would then name the adapters it reads, while any backend adapter fills `backend`, and the check rule of `lib.mkClaimKind` receives the kind's settings at `contracts.kinds.<kind>`, so the generators must sit there for the check to read them.
- **A name field in each slot**, so messages name the imported adapter. Messages say "the secret backend" and list its generators instead, and the module system already names both files when a second adapter defines a slot.

## Consequences

- The backend's data comes from one definition, and null says that no adapter is imported, in place of a `path` default that fails and a null generator list.
- A node that replaces part of a slot, such as the backend's `path`, replaces the whole slot with `lib.mkForce`, generators included.
- The slot type keeps its message through the module system's submodule substitution, which `types.unique` loses in nixpkgs.
- `lib.mkClaimKind` declares a kind's slots with its settings and hands both to the check rule as `settings`.
