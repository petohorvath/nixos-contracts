{ contracts, lib }:
let
  inherit (contracts) nodesOf;
  inherit (import ../fixtures/inboxes.nix)
    service
    failuresOf
    telegraf
    tokenOf
    writers
    copyingInfluxdb
    ;
in
{
  testCopyOfACopiedOrDerivedSecretFailsTheCopysCheck = {
    expr =
      map
        (
          value:
          failuresOf
            (nodesOf {
              metrics = [
                (service "telegraf" {
                  secrets = {
                    origin.value.generated = "alnum";
                    token = {
                      inherit value;
                      sendTo = [ writers ];
                    };
                  };
                })
              ];
              store = [ (copyingInfluxdb { static.user = "influxdb2"; } { }) ];
            }).store
        )
        [
          {
            copied = (tokenOf "metrics") // {
              id = "origin";
            };
          }
          { derived.generator = "basic-auth"; }
        ];
    expected = lib.replicate 2 [
      "nixos-contracts: secrets claim `influxdb.writers.metrics.telegraf.token`: it references `metrics:secrets.telegraf.token`, which is copied or derived itself; reference a provided or generated secret."
    ];
  };

  testCopyItsDynamicIdentityCannotReadFailsTheReadabilityCheck = {
    expr =
      failuresOf
        (nodesOf {
          metrics = [ (telegraf [ writers ]) ];
          store = [ (copyingInfluxdb { dynamic.unit = "influxdb.service"; } { }) ];
        }).store;
    expected = [
      "nixos-contracts: secrets claim `influxdb.writers.metrics.telegraf.token`: its dynamic identity cannot read it; import a delivery adapter such as `nixosModules.systemd-credentials`, or give the identity a `sharedGroup` and the secret that group."
    ];
  };
}
