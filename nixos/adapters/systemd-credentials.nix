/*
  Deliver every secret of a dynamic-identity service into its unit with
  `LoadCredential=`, so the dynamic user reads it under
  `/run/credentials/<unit>/<service>-<id>`. Loads from the location a secret
  backend adapter sets, so import one beside it.
*/
{ config, lib, ... }:
let
  inherit (config.contracts.secrets) location;

  serviceNameOf = unit: lib.removeSuffix ".service" unit;

  delivered = lib.filter (secret: secret.delivered) (
    lib.attrValues config.contracts.claimSets.secrets
  );

  units = lib.unique (map (secret: secret.unit) delivered);

  # The delivery itself defines the unit's `systemd.services` entry, so the
  # unit exists only if another module gave it a command, an `ExecStart` set
  # directly or through `script`.
  unitAssertions =
    unit:
    let
      service = config.systemd.services.${serviceNameOf unit} or { serviceConfig = { }; };
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
    contracts.secrets.delivery = { unit, name }: "/run/credentials/${unit}/${name}";

    systemd.services = lib.mkIf (location != null) (
      lib.mkMerge (
        map (secret: {
          ${serviceNameOf secret.unit}.serviceConfig.LoadCredential = [
            "${secret.name}:${location secret.name}"
          ];
        }) delivered
      )
    );

    contracts.assertions = [
      {
        assertion = delivered == [ ] || location != null;
        message = "delivering secrets needs a secret backend adapter that sets `contracts.secrets.location`.";
      }
    ]
    ++ lib.concatMap unitAssertions units;
  };
}
