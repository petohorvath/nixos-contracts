{ helpers, ... }:
let
  inherit (helpers.contracts) evaluate failures;

  service = name: binds: {
    contracts.services.${name} = {
      enable = true;
      identity.static.user = name;
      inherit binds;
    };
  };
  clashes =
    first: second:
    failures [
      (service "first" { listen = first; })
      (service "second" { listen = second; })
    ];
in
{
  testBindDefaultsToTcpOnEveryIpv4Address = {
    expr = (evaluate [ (service "web" { http.port = 80; }) ]).contracts.claimSets.binds.web.http;
    expected = {
      service = "web";
      id = "http";
      name = "local_binds_web_http";
      ref = {
        node = "local";
        kind = "binds";
        service = "web";
        id = "http";
      };
      protocols = [ "tcp" ];
      port = 80;
      addresses = [ "0.0.0.0" ];
      bindpoints = [ "0.0.0.0:80" ];
    };
  };

  testBindpointsBracketIpv6Addresses = {
    expr =
      (evaluate [
        (service "dns" {
          dns = {
            port = 53;
            addresses = [
              "127.0.0.1"
              "::1"
            ];
          };
        })
      ]).contracts.services.dns.binds.dns.bindpoints;
    expected = [
      "127.0.0.1:53"
      "[::1]:53"
    ];
  };

  testBindRejectsAnUnknownProtocol = {
    expr =
      (evaluate [
        (service "web" {
          http = {
            port = 80;
            protocols = "quic";
          };
        })
      ]).contracts.services.web.binds.http.protocols;
    expectedError.msg = "contracts\\.services\\.web\\.binds\\.http\\.protocols' is not of type";
  };

  testBindRejectsAnInvalidAddress = {
    expr =
      (evaluate [
        (service "web" {
          http = {
            port = 80;
            addresses = "localhost";
          };
        })
      ]).contracts.services.web.binds.http.addresses;
    expectedError.msg = "contracts\\.services\\.web\\.binds\\.http\\.addresses' is not of type";
  };

  testUnspecifiedAddressClashesWithItsFamily = {
    expr = clashes { port = 80; } {
      port = 80;
      addresses = "10.0.0.1";
    };
    expected = [
      "nixos-contracts: binds claims `first.listen` and `second.listen` clash: both listen on tcp port 80, at `0.0.0.0` and `10.0.0.1`."
    ];
  };

  testIpv6UnspecifiedAddressClashesWithIpv4 = {
    expr = clashes { port = 80; } {
      port = 80;
      addresses = "::";
    };
    expected = [
      "nixos-contracts: binds claims `first.listen` and `second.listen` clash: both listen on tcp port 80, at `0.0.0.0` and `::`."
    ];
  };

  testIpv4UnspecifiedAddressDoesNotCoverIpv6 = {
    expr = clashes { port = 80; } {
      port = 80;
      addresses = "fd00::1";
    };
    expected = [ ];
  };

  testSpecificAddressesOfTwoFamiliesDoNotClash = {
    expr =
      clashes
        {
          port = 80;
          addresses = "10.0.0.1";
        }
        {
          port = 80;
          addresses = "fd00::1";
        };
    expected = [ ];
  };

  testDistinctAddressesDoNotClash = {
    expr =
      clashes
        {
          port = 80;
          addresses = "10.0.0.1";
        }
        {
          port = 80;
          addresses = "10.0.0.2";
        };
    expected = [ ];
  };

  testEquivalentIpv6SpellingsClash = {
    expr = builtins.length (
      clashes
        {
          port = 53;
          addresses = "fd00::1";
        }
        {
          port = 53;
          addresses = "fd00:0::1";
        }
    );
    expected = 1;
  };

  testProtocolsDoNotClash = {
    expr = clashes { port = 53; } {
      port = 53;
      protocols = "udp";
    };
    expected = [ ];
  };

  testSharedProtocolOfAListClashes = {
    expr =
      clashes
        {
          port = 53;
          protocols = [
            "tcp"
            "udp"
          ];
        }
        {
          port = 53;
          protocols = "udp";
        };
    expected = [
      "nixos-contracts: binds claims `first.listen` and `second.listen` clash: both listen on udp port 53, at `0.0.0.0` and `0.0.0.0`."
    ];
  };

  testOverlappingPortRangesClash = {
    expr = clashes { port = "5000-5100"; } { port = 5050; };
    expected = [
      "nixos-contracts: binds claims `first.listen` and `second.listen` clash: both listen on tcp ports 5000-5100 and 5050, at `0.0.0.0` and `0.0.0.0`."
    ];
  };

  testAdjacentPortRangesDoNotClash = {
    expr = clashes { port = "5000-5100"; } { port = "5101-5200"; };
    expected = [ ];
  };

  testBindsOfOneServiceClashToo = {
    expr = builtins.length (failures [
      (service "web" {
        http.port = 80;
        alt.port = 80;
      })
    ]);
    expected = 1;
  };
}
