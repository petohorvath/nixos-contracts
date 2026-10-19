{ nixos, module }:
let
  inherit (nixos) evaluate failures;

  web = name: {
    contracts.services.${name} = {
      enable = true;
      identity.static.user = name;
      binds.http.port = 80;
    };
  };
in
{
  testNixosModuleReportsClashes = {
    expr = failures [
      module
      (web "first")
      (web "second")
    ];
    expected = [
      "nixos-contracts: binds claims `first-http` and `second-http` clash: both listen on tcp port 80, at `0.0.0.0` and `0.0.0.0`."
    ];
  };

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
        "nixos-contracts: binds claims `first-http` and `second-http` clash: both listen on tcp port 80, at `0.0.0.0` and `0.0.0.0`."
        (map (check: check.message) failedAssertions);
    expected = true;
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
      ]).contracts.claimSets.binds.first-http.port;
    expected = 80;
  };
}
