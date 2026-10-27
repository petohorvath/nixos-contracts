---
status: accepted
---

# Check a reference's shape and names before resolving it

A reference is checked in two stages. Its shape comes first: a value that is not an attribute set, misses one of `node`, `kind`, `service` and `id`, or holds any other field fails as soon as `contracts.resolve` is called, with a message naming the reference. Its names come second: a reference of the right shape whose node identity, kind name, service name or id breaks its name rule gets a `reason` naming the name and its allowed characters, as any other reference that names no claim does. Reading `reason` stays safe for every reference of the right shape. This supersedes ADR-0021 in part, under which reading `reason` never failed.

A reference written as a literal, outside a typed field, reached `contracts.resolve` unchecked. Without a `kind` it failed with Nix's `attribute 'kind' missing`, naming neither the reference nor the library, and with a name no claim can carry, such as the service `web_proxy`, it gave the reason "no enabled contract holds it", which hides the typo. `lib.mkReference` and the reference types now apply the same checks where a reference is written, and `contracts.resolve` keeps them for a reference built any other way.

## Considered Options

- **Give a malformed reference a `reason` too.** Reading `reason` would never fail, as ADR-0021 has it, but the reason and the lazy error of `claim` and `config` name the reference by its four fields, and a malformed reference lacks them. A label with gaps for the missing fields would name a reference no one wrote.
- **Fail on a name that breaks its rule.** A secret's checks read each reference's `reason` together, so one invalid name would hide the other failed checks instead of being reported among them.
- **Ignore unknown fields.** A secret's `sources` entry, a reference with its `claim`, would resolve as it is, but a misspelt field, such as `servce` beside a missing `service`, would be reported as the missing field alone, and a value that only resembles a reference would pass.

## Consequences

- A caller that passes `contracts.resolve` a value with extra fields removes them first. The agenix-rekey adapter resolves a secret's source as `removeAttrs source [ "claim" ]`.
- `lib.mkReference` builds a reference in code with the same checks. It does not reverse ADR-0012, which turned a helper down as a substitute for `lib.types.referenceTo` defaulting the kind; a typed field still takes `{ node; service; id; }`.
- `lib.types.reference` and `lib.types.referenceTo` check the name rules of ADR-0017 and ADR-0018 at definition, so an invalid name in a typed field fails as a type error where it is written, before it reaches `contracts.resolve`.
