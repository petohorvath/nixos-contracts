# A host that runs influxdb, maps its storage class and secrets directories,
# and narrows the service to loopback.
{
  services.influxdb2.enable = true;

  age.rekey = {
    secretsDir = ./secrets;
    generatedSecretsDir = ./secrets/generated;
  };

  contracts = {
    mounts.classes = [ "state" ];
    adapters.preservation.roots.state = "/persist/state";
    # This host differs from the service module's default in one field.
    services.influxdb.binds.http.addresses = [ "127.0.0.1" ];
  };
}
