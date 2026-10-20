---
status: accepted
---

# Mark a generated secret by its generator

A secret names its generator in a nullable `generator` field, and a secret without one is provided by a person. The field replaces a required tag, `provenance`, that held exactly one of `provided = { }` or `generated = <name>`. The tag made every secret state where its value comes from, but it needed an empty attribute set to say "provided", the name `provenance` read as jargon while `source` would suggest a file path, and a host could switch a secret between the two only with `lib.mkForce`, since a default-priority tag still counts as defined. With a plain field, a host overrides a service module's generated secret by setting `generator = null`, and the name matches agenix-rekey's own `generator`.

## Consequences

A provided secret is the silent default, so forgetting a generator yields a secret a person must supply rather than an evaluation error. A backend adapter catches the missing value instead: `nixosModules.agenix-rekey` fails a check when a provided secret has no encrypted file.
