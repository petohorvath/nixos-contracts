{ helpers, ... }:
let
  inherit (helpers.nixos) evaluate evaluateWithoutNode;
  module = helpers.nixos.nixosModules.default;

  web = name: {
    contracts.services.${name} = {
      enable = true;
      identity.static.user = name;
      binds.http.port = 80;
    };
  };
in
{
  # NixOS's own assertions fail too without a bootloader, so look for the
  # failure among them.
  testNixosModuleForwardsFailuresToAssertions = {
    expr =
      let
        failedAssertions =
          builtins.filter (check: !check.assertion)
            (evaluate [
              module
              (web "first")
              (web "second")
            ]).assertions;
      in
      builtins.elem
        "nixos-contracts: binds claims `first.http` and `second.http` clash: both listen on tcp port 80, at `0.0.0.0` and `0.0.0.0`."
        (map (check: check.message) failedAssertions);
    expected = true;
  };

  # Reads `assertions` rather than `contracts.failures`, so forwarding the
  # checks to NixOS is what fails.
  testNixosModuleRequiresANodeIdentity = {
    expr = map (check: check.assertion) (evaluateWithoutNode [ module ]).assertions;
    expectedError.msg = "contracts\\.node' was accessed but has no value defined";
  };

  testNixosModuleWiresADaemonFromItsContract = {
    expr =
      (evaluate [
        module
        (web "first")
        (
          { config, ... }:
          {
            services.nginx = {
              enable = true;
              defaultHTTPListenPort = config.contracts.services.first.binds.http.port;
            };
          }
        )
      ]).services.nginx.defaultHTTPListenPort;
    expected = 80;
  };

  testNixosModuleImportedTwiceDeclaresItsOptionsOnce = {
    expr =
      (evaluate [
        module
        module
        (web "first")
      ]).contracts.claimSets.binds.first.http.port;
    expected = 80;
  };
}
