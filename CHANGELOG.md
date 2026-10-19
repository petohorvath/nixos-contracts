# Changelog

## Unreleased

### Added

- Contracts at `contracts.services.<service>`, each with an `enable` and a required static or dynamic `identity`.
- Claim kinds `binds`, `mounts` and `secrets`, whose mount and secret owners and groups default from the service's identity, with read-only claim sets at `contracts.claimSets.<kind>`, and clash checks and a check that a dynamic identity can read its secrets in `contracts.assertions`.
- `contracts.mounts.classes`, and the `contracts.secrets.location` and `contracts.secrets.delivery` rules for adapters.
- `lib.mkClaimKind`, for defining further claim kinds with their own clash and check rules, and `lib.mkDefaultContract`, for contracts a host can override field by field.
- `nixosModules.default`, which forwards the checks to NixOS `assertions`, and `modules.generic.default` for any module class.
- Examples for a static-identity service (influxdb2), a dynamic-identity service (alloy) and a project-defined claim kind, evaluated by the checks.
- Adapters `nixosModules.preservation` (mounts into `preservation.preserveAt` by class root), `nixosModules.agenix-rekey` (secrets into `age.secrets`, with a `secretsDir` convention and per-secret `rekeyFiles`), and `nixosModules.systemd-credentials` (a dynamic identity's secrets into its unit's `LoadCredential=`).
