---
status: accepted
---

# Settle a tag by the priority of its definitions

An option that holds exactly one of several tags, such as a contract's `identity` or a secret's `value`, has the type `lib.types.tag`, which keeps the tag of its strongest definition and drops the definitions of other tags, while two tags of one priority still fail, as with `lib.types.attrTag`. A definition counts at the priority of the strongest override inside it, each leaf at its innermost override, so a tag that `lib.mkDefaultContract` writes, marking each leaf, gives way to a tag a node writes at normal priority. `lib.types.attrTag` counts every definition, so a node switching a module's tag, such as a static identity to a dynamic one, would need `lib.mkForce`.

## Considered Options

- **Mark the tag rather than each leaf in `lib.mkDefaultContract`.** The tag would then give way to a normal definition under `lib.types.attrTag` alone, but `lib.mkDefaultContract` cannot tell a tag from another attribute set without the contract's types, and a module that writes `mkDefault` on a leaf by hand would still fail.
- **A tag of `lib.types.attrTag` with a discriminating field, such as `kind = "copied"`.** One field switches the case, but the other cases' fields stay defined and the type cannot reject them.

## Consequences

- A tag switches like a plain field, so a field that holds one of several cases says so in its type.
- The tag type is generic and lives in the core, so a project's claim kind gets the same switching for its own tags.
- The definitions of the winning tag merge, each leaf at its own priority. A node that writes one leaf of another tag at normal priority, such as `identity.dynamic.unit`, replaces the module's tag, while one that writes a leaf of the module's own tag merges with its other leaves, such as a secret's `value.generated.from` beside the module's generator.
- A prototype on the `prototype/claim-inboxes` branch, commit `c101bce`, switched a default-priority `generated` value to `copied` and a static identity to a dynamic one at normal priority, and two tags of one priority still failed.
