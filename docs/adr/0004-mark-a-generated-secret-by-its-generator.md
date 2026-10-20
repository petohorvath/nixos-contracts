---
status: accepted
---

# Mark a generated secret by its generator

A secret names its generator in a nullable `generator` field, and a secret without one is provided by a person. A plain field is simpler to write than a tag, matches agenix-rekey's own `generator`, and lets a host make a generated secret from `lib.mkDefaultContract` provided by setting `generator = null`, without `lib.mkForce`.

## Considered Options

A required tag, `provenance`, holding exactly one of `provided = { }` or `generated = <name>`, made every secret state where its value comes from. It needed an empty attribute set to say "provided", and switching a default-priority tag needed `lib.mkForce`, since the old tag still counts as defined. Naming the tag `source` instead would have suggested a file path, which is a backend concern.

## Consequences

A provided secret is the silent default, so a forgotten generator yields a secret a person must supply rather than an evaluation error. A backend adapter catches the missing value instead: `nixosModules.agenix-rekey` fails a check when a provided secret has no encrypted file.
