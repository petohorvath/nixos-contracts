# A host that runs influxdb, maps its storage class and secrets directory, and
# narrows the service to loopback.
{
  services.influxdb2.enable = true;

  contracts = {
    mounts.classes = [ "state" ];
    adapters = {
      preservation.roots.state = "/persist/state";
      agenixRekey.secretsDir = ./secrets;
    };
    # This host differs from the service module's default in one field.
    services.influxdb.binds.http.addresses = [ "127.0.0.1" ];
  };
}
