---
status: accepted
---

# Say where a secret's value comes from on the secret

A secret holds no value, but its `value` says where the value comes from, as one of three tags ([ADR-0006](0006-settle-a-tag-by-the-priority-of-its-definitions.md)): `provided = { }`, the default; `generated = { generator; from; }`, for a value a named generator makes, alone or from the secrets `from` references; and `copied = <reference>`, for a copy of one other secret, on this node or another ([ADR-0008](0008-address-a-claim-by-an-absolute-reference.md)). Whether a service makes its own value is a fact the service module knows, and a copy or a value made from others is a claim of the service that reads it, so a service module writes no backend option, and the reading contract's ownership, checks and `path` cover the value ([ADR-0013](0013-leave-carrying-a-reference-between-nodes-to-the-fleet.md)). A copy reads any secret but a copy, and a generator only secrets that reference none, so the core never follows a chain of references.

## Considered Options

- **Leave the value to the backend entirely.** The library needs no concept of a value, but a service module with a generated secret would write `age.secrets.<name>.generator`, type the backend name by hand and fail to evaluate without agenix, and a copy would stay outside the claim of the service that reads it.
- **Configuration-wide secret values, named by claims, holding the generator and its inputs.** They add a concept the library only translates to agenix-rekey, and the translation fails where a value is made from others: agenix-rekey's `generator.dependencies` name other nodes' `age.secrets` entries, and a value name gives neither an entry's name nor, for a value one node generates, its encrypted file.
- **Nullable `generate` and `from` fields.** Which case a secret is follows from two fields, a check rejects their invalid combinations, such as a copy of several secrets, and the type tells a reader nothing of the cases.
- **A separate `derived` tag beside `generated = "<generator>"`.** A `derived` value with an empty `from` means what a `generated` one does, so one value has two spellings, and a receiver that builds `from` from a fleet's shared data, such as one htpasswd line per client, would switch tags when the list is empty.
- **A generator described by its output, such as a length and a character set.** It has no counterpart for a generator like `dhparams`, so a value names one of the backend's generators instead.

## Consequences

- A backend adapter turns the generator into the backend's own and lists the backend's generators in its slot ([ADR-0005](0005-hold-adapter-data-in-slots-not-kind-settings.md)), so a check catches a misspelt generator name. No generator is checked while no backend adapter is imported, and a configuration that changes its backend may need to rename them.
- A secret's read-only `generator`, `{ name; sources; }` for a `generated` value, and `copyOf`, the source of a `copied` value, say where its value comes from, so a backend adapter reads them rather than the tags ([ADR-0016](0016-hold-a-secrets-sources-on-its-copy-and-its-generator.md)).
- Anything else about the value, such as a provided secret's encrypted file, is set on the backend entry under the claim's backend name. A generator script set there overrides the claim's generator, and dependencies set there keep it; only the claim's `value.provided = { }` removes it, so whether the service makes its value stays stated in one place.
- `provided` is the default, so a forgotten generator gives a secret a person must supply rather than an evaluation error. The backend adapter catches the missing value: the agenix-rekey adapter fails a check for a secret without an encrypted file. That adapter has no settings, since agenix-rekey's own `secretsDir`, `generatedSecretsDir` and `rekeyFile` locate the files.
- A copy reads the encrypted file of the secret it references, never that secret's references, so a copy of a secret generated from others, such as an htpasswd, reads its file, and two copies referencing each other fail their checks instead of recursing. Two nodes whose generators read each other's secrets cannot form a cycle.
- A check names the rule a reference breaks. A copy that references a copy is told the secret that copy references, which it may reference instead, and a generator that references a copy or a secret generated from others is told that a generator reads only secrets that reference none.
- A node adds references to a module's generated secret by writing `value.generated.from` alone, which merges with the module's generator.
- Key pairs whose public half other configurations read, such as WireGuard or SSH host keys, need a claim kind of their own.
