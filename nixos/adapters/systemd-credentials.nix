/*
  Deliver every delivered secret into the unit it names with
  `LoadCredential=`, so the unit reads it under
  `/run/credentials/<unit>/<service>_<id>`, such as `alloy_loki-password`.
  Loads from the path a secret backend adapter sets in
  `contracts.kinds.secrets.backend`, so import one beside it.
*/
{ config, lib, ... }:
let
  inherit (config.contracts.kinds.secrets) backend;
  inherit (import ../../modules/references.nix) backendNameOf backendPathOf claimsOf;

  toServiceName = unit: lib.removeSuffix ".service" unit;

  delivered = lib.filter (secret: secret.delivered) (claimsOf config.contracts.claimSets.secrets);

  # A dynamic identity's secret is delivered only to the identity's unit,
  # which the secrets check enforces.
  isDynamic = secret: config.contracts.services.${secret.service}.identity ? dynamic;

  unitsOf = secrets: lib.unique (map (secret: secret.unit) secrets);

  systemdServiceOf = unit: config.systemd.services.${toServiceName unit} or { serviceConfig = { }; };

  # The delivery itself defines the unit's `systemd.services` entry, so the
  # unit exists only if another module gave it a command, an `ExecStart` set
  # directly or through `script`.
  mkUnitAssertion = unit: {
    assertion = lib.hasSuffix ".service" unit && (systemdServiceOf unit).serviceConfig ? ExecStart;
    message = "secrets are delivered to unit `${unit}`, which is not a service defined in `systemd.services`.";
  };

  mkDynamicUnitAssertion =
    unit:
    let
      service = systemdServiceOf unit;
    in
    {
      assertion = !(service.serviceConfig ? ExecStart) || (service.serviceConfig.DynamicUser or false);
      message = "dynamic identity unit `${unit}` does not set `DynamicUser`.";
    };
in
{
  config = {
    contracts.kinds.secrets.delivery.path =
      args@{ unit, ... }: "/run/credentials/${unit}/${backendNameOf args}";

    systemd.services = lib.mkMerge (
      map (secret: {
        ${toServiceName secret.unit}.serviceConfig.LoadCredential = [
          "${backendNameOf secret}:${backendPathOf backend secret}"
        ];
      }) delivered
    );

    contracts.assertions =
      map mkUnitAssertion (unitsOf delivered)
      ++ map mkDynamicUnitAssertion (unitsOf (lib.filter isDynamic delivered));
  };
}
