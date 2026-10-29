---
status: accepted
---

# Hold a secret's sources on its copy and its generator

A secret tells a reader where its value comes from through two read-only facts, and only the secrets kind reads its `value` tag. `copyOf` is the source of a `copied` value, or null. `generator` is `{ name; sources; }` for a `generated` value, with one source for each reference of its `from` in order, or null. A source is `{ reference; reason; }`: the reference as written, and a null reason, or why the secret cannot read the secret it names. That reason is either one `contracts.resolve` gives or one of the value's own rules. The secrets check reports the reasons of a claim's sources, so each reference is judged once. The read-only `sources`, which held each reference with the claim it resolves to, is removed, and a caller no longer removes `claim` from a source before resolving it ([ADR-0007](0007-say-where-a-secrets-value-comes-from-on-the-secret.md), [ADR-0011](0011-resolve-and-check-a-reference-in-the-core.md)).

A secret's read-only `generator`, a string, let a backend adapter read the generator instead of the tags, but whether a secret was a copy still crossed into the agenix-rekey adapter. It tested `value ? copied`, assumed a copy's `sources` held one entry, and named the copied secret from `value.copied`. The check and `sources` each resolved a reference and kept different halves of the result. The check kept the reason and `sources` kept the claim, so the adapter took a null claim to mean that the check had reported the reference. The adapter also stripped `claim` from a source to resolve it again for the node's configuration, since [ADR-0011](0011-resolve-and-check-a-reference-in-the-core.md) returns that configuration only from `contracts.resolve`. A source's claim was then a second, partial copy of what `contracts.resolve` returns. It also nested another node's claim, with fields that node derives, in this configuration's claim set.

## Considered Options

- **Tell a copy from the facts already there, by a null `generator` and non-empty `sources`.** No field is added, but the adapter still assumes one source, and a later tag with references and no generator would pass for a copy.
- **Add `copyOf` and keep `sources`.** The adapter stops reading tags, but a copy's reference sits in two fields, and the check and the adapter still resolve each reference apart.
- **Keep a flat source and add `reason`, as `{ node; kind; service; id; claim; reason; }`.** A caller would still remove fields before resolving it.
- **Let `contracts.resolve` ignore fields it does not know.** A source would resolve as it is, but ADR-0011 turned this down, since a misspelt field would be reported as a missing one.
- **Keep the resolved `claim` in a source, null when rejected.** A reader would get the claim without a call, but the claim set would still nest other nodes' claims, and a claim would come from two places.

## Consequences

- A backend adapter reads `copyOf`, `generator.name` and `generator.sources`, skips a source whose `reason` is set, and reads the claim and node configuration a source names from `contracts.resolve source.reference`. The agenix-rekey adapter no longer reads `value` or removes fields.
- A copy whose reference is rejected keeps its `copyOf`, with the reason, so it still reads as a copy and the adapter raises no second failure for its missing encrypted file.
- The secrets kind still reads the tags of a referenced secret to apply its rules, never that secret's sources, so the core follows no chain of references, as ADR-0007 requires.
- A claim set no longer holds another node's claims, only references and reasons.
