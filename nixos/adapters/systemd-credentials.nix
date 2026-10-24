/*
  Deliver every secret of a dynamic-identity service into its unit with
  `LoadCredential=`, so the dynamic user reads it under
  `/run/credentials/<unit>/<service>-<id>`. Loads from the location a secret
  backend adapter sets in `contracts.kinds.secrets.backend`, so import one
  beside it.
*/
{ config, lib, ... }:
let
  inherit (config.contracts.kinds.secrets) backend;

  nameOf = address: lib.concatStringsSep "-" address;

  location =
    address:
    if backend == null then
      throw "nixos-contracts: secret `${nameOf address}` has no location: import a secret backend adapter such as `nixosModules.agenix-rekey`, which sets `contracts.kinds.secrets.backend`"
    else
      backend.location address;

  toServiceName = unit: lib.removeSuffix ".service" unit;

  # PROTOTYPE: authored claims and received copies alike.
  delivered = lib.filter (secret: secret.delivered) (
    lib.concatMap lib.attrValues (lib.attrValues config.contracts.claimSets.secrets)
    ++ config.contracts.copies
  );

  units = lib.unique (map (secret: secret.unit) delivered);

  # The delivery itself defines the unit's `systemd.services` entry, so the
  # unit exists only if another module gave it a command, an `ExecStart` set
  # directly or through `script`.
  mkUnitAssertions =
    unit:
    let
      service = config.systemd.services.${toServiceName unit} or { serviceConfig = { }; };
    in
    [
      {
        assertion = lib.hasSuffix ".service" unit && service.serviceConfig ? ExecStart;
        message = "dynamic identity unit `${unit}` is not a service defined in `systemd.services`.";
      }
      {
        assertion = !(service.serviceConfig ? ExecStart) || (service.serviceConfig.DynamicUser or false);
        message = "dynamic identity unit `${unit}` does not set `DynamicUser`.";
      }
    ];
in
{
  config = {
    contracts.kinds.secrets.delivery.path =
      { unit, address }: "/run/credentials/${unit}/${nameOf address}";

    systemd.services = lib.mkMerge (
      map (secret: {
        ${toServiceName secret.unit}.serviceConfig.LoadCredential = [
          "${nameOf secret.address}:${location secret.address}"
        ];
      }) delivered
    );

    contracts.assertions = lib.concatMap mkUnitAssertions units;
  };
}
