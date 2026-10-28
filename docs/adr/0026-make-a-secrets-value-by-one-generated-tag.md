---
status: accepted
---

# Make a secret's value by one generated tag

A secret's `value` holds one of three tags: `provided = { }`, `generated = { generator; from; }` for a value a generator makes, alone or from the secrets `from` references, and `copied = <reference>`. `from` defaults to `[ ]`. This supersedes ADR-0013 in part, whose `generated = "<generator>"` and `derived = { generator; from; }` both named a generator. A `derived` value with an empty `from` meant what a `generated` one did, yet a copy could read a `generated` secret and not a `derived` one, since the core told the secrets a reference may name by their tags.

The core states that rule by references instead. A copy reads any secret but a copy, so two copies referencing each other still fail their checks instead of recursing, and a copy of a secret generated from others, such as an htpasswd, reads that secret's encrypted file. This supersedes ADR-0007 in part, whose checks failed a reference to any secret with references of its own: a copy reads the encrypted file of the secret it references, never that secret's references, so it follows no chain. A generator still reads only secrets that reference none, as ADR-0007 required, so the core never follows a chain of references and two nodes whose generators read each other's secrets cannot form a cycle.

## Considered Options

- **Require a non-empty `from` on `derived`.** It removes the overlap with the smallest change, but a receiver that builds `from` from a fleet's shared data, such as one htpasswd line per client, would switch tags when the list is empty.
- **Keep `generated = "<generator>"` as a shorthand.** It keeps the common case short, but gives one value two spellings, which is what this decision removes.

## Consequences

- A node adds references to a module's generated secret by writing `value.generated.from` alone, which merges with the module's generator, rather than switching to another tag and restating the generator. This contradicts ADR-0013's consequence that a node writing one leaf of a module's tag replaces the whole tag: the tag type keeps every definition of the winning tag, so the leaves of one tag merge at their own priorities, as the API reference documents.
- A check names the rule a reference breaks. A copy that references a copy is told the secret that copy references, which it may reference instead; a generator that references a copy or a secret generated from others is told that a generator reads only secrets that reference none, since the core does not follow the chain to find one.
