# Changelog

## Unreleased

### Added

- Contracts at `contracts.services.<service>`, each with an `enable` and a required static or dynamic `identity`.
- Claim kinds `binds`, `mounts` and `secrets`, with read-only claim sets at `contracts.claimSets.<kind>` carrying resolved owners and groups, and clash checks in `contracts.assertions`.
- `contracts.mounts.classes`, and the `contracts.secrets.location` and `contracts.secrets.delivery` rules for adapters.
- `lib.mkClaimKind`, for defining further claim kinds, and `lib.mkDefaultContract`, for contracts a host can override field by field.
- `nixosModules.default`, which forwards the checks to NixOS `assertions`, and `modules.generic.default` for any module class.
- Adapters `nixosModules.preservation` (mounts into `preservation.preserveAt` by class root), `nixosModules.agenix-rekey` (secrets into `age.secrets`, with a `secretsDir` convention and per-secret `rekeyFiles`), and `nixosModules.systemd-credentials` (a dynamic identity's secrets into its unit's `LoadCredential=`).
