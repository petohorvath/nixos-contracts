---
status: accepted
---

# Settle a tag by the priority of its definitions

An option that holds exactly one of several tags, such as a contract's `identity` or a secret's `value`, keeps the tag of its strongest definition and drops the definitions of other tags. A definition's priority is that of the strongest override inside it, each leaf at the priority of its innermost override, so a tag that `lib.mkDefaultContract` writes, marking each leaf rather than the tag, gives way to a tag a node writes at normal priority. Two tags of one priority still fail, as with `lib.types.attrTag`. A secret's value is one such tag: `provided = { }`, the default, for a value a person or another party provides; `generated = <generator>` for one the service makes; `copied = <reference>` for a copy of one secret; and `derived = { generator; from; }` for one a generator makes from the secrets it references. This supersedes ADR-0006 in part, which marked a generated secret by a nullable `generate`, and ADR-0007 in part, which named the secrets a value comes from in `from` and told a copy from a derived value by whether `generate` was set.

ADR-0004 and ADR-0006 rejected a tag for the value because switching a tag of default priority needed `lib.mkForce`: the module system's tag counts every definition, so a node that wrote `generated` over a module's `provided` defined two tags. The same flaw already made a node switch a module's static identity to a dynamic one with `lib.mkForce`. Settled by priority, the tag switches like a plain field, and it states in one place what the fields `generate` and `from` stated together: a copy that references several secrets, or a value both generated and copied, cannot be written, so the checks for them go.

## Considered Options

- **Keep `generate` and `from`.** Switching needs no `lib.mkForce`, but which of four cases a secret is follows from two fields, a check rejects their invalid combinations, and the type tells a reader nothing of the cases.
- **Mark the tag rather than each leaf in `lib.mkDefaultContract`.** The tag would then give way to a normal definition under `lib.types.attrTag` alone, but `lib.mkDefaultContract` cannot tell a tag from another attribute set without the contract's types, and a module that writes `mkDefault` on a leaf by hand would still fail.
- **A tag of `lib.types.attrTag` with a discriminating field, such as `kind = "copied"`.** One field switches the case, but the other cases' fields stay defined and the type cannot reject them.

## Consequences

- The tag type is generic and lives in the core, so a new claim kind gets the same switching for its own tags.
- A node that writes one leaf of a module's tag at normal priority, such as `identity.dynamic.unit`, replaces the whole tag, including the leaves of the same tag that the module wrote.
- A secret carries a read-only `sources`, the references of `copied` or `derived` with the claims they resolve to, in place of ADR-0011's `referenced`. Only a `provided` or `generated` secret resolves, so a copy of a copy fails its check as before.
- A prototype on the `prototype/claim-inboxes` branch, commit `c101bce`, switched a default-priority `generated` value to `copied` and a static identity to a dynamic one at normal priority, and two tags of one priority still failed.
