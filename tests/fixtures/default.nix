# The source files that suites name, and the evaluated examples, built from
# the source exports.
{
  backends,
  exports,
  lib,
  nixpkgs,
  system,
}:
let
  exampleArgs = {
    inherit
      backends
      exports
      nixpkgs
      system
      ;
  };
in
{
  # Source files by name, for the suites that check where an option comes
  # from.
  sourceFiles = {
    core = ../../modules/core.nix;
    assertions = ../../nixos/assertions.nix;
    agenix-rekey = ../../nixos/adapters/agenix-rekey.nix;
    preservation = ../../nixos/adapters/preservation.nix;
    systemd-credentials = ../../nixos/adapters/systemd-credentials.nix;
  };

  examples = {
    alloy = import ../../examples/alloy exampleArgs;
    custom-kind = import ../../examples/custom-kind { inherit exports lib; };
    exporter = import ../../examples/exporter { inherit exports nixpkgs system; };
    grafana = import ../../examples/grafana exampleArgs;
    influxdb = import ../../examples/influxdb exampleArgs;
    shared-token = import ../../examples/shared-token exampleArgs;
  };
}
