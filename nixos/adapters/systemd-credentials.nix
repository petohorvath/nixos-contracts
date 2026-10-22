/*
  Deliver every secret of a dynamic-identity service into its unit with
  `LoadCredential=`, so the dynamic user reads it under
  `/run/credentials/<unit>/<service>-<id>`. Loads from the location a secret
  backend adapter sets, so import one beside it.
*/
{ config, lib, ... }:
let
  inherit (config.contracts.kinds.secrets) location;

  toServiceName = unit: lib.removeSuffix ".service" unit;

  delivered = lib.filter (secret: secret.delivered) (
    lib.attrValues config.contracts.claimSets.secrets
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
    contracts.kinds.secrets.delivery = { unit, name }: "/run/credentials/${unit}/${name}";

    systemd.services = lib.mkMerge (
      map (secret: {
        ${toServiceName secret.unit}.serviceConfig.LoadCredential = [
          "${secret.name}:${location secret.name}"
        ];
      }) delivered
    );

    contracts.assertions = lib.concatMap mkUnitAssertions units;
  };
}
