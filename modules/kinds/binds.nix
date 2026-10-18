# Binds: where a service accepts traffic.
{ libnet }:
{ lib, ... }:
let
  inherit (libnet) ip port portRange;

  toPortRange =
    value:
    if builtins.isInt value then portRange.fromPort (port.fromInt value) else portRange.parse value;

  # The unspecified address of a family covers every address of that family.
  addressesOverlap =
    first: second:
    let
      a = ip.parse first;
      b = ip.parse second;
    in
    ip.version a == ip.version b && (ip.isUnspecified a || ip.isUnspecified b || ip.eq a b);

  conflict =
    first: second:
    let
      protocols = lib.intersectLists first.proto second.proto;
      addressPairs = lib.filter (pair: addressesOverlap pair.first pair.second) (
        lib.cartesianProduct {
          first = first.addresses;
          second = second.addresses;
        }
      );
    in
    if
      protocols != [ ]
      && portRange.overlaps (toPortRange first.port) (toPortRange second.port)
      && addressPairs != [ ]
    then
      let
        pair = builtins.head addressPairs;
        ports =
          if first.port == second.port then
            "port ${toString first.port}"
          else
            "ports ${toString first.port} and ${toString second.port}";
      in
      "both listen on ${lib.concatStringsSep "/" protocols} ${ports}, at `${pair.first}` and `${pair.second}`"
    else
      null;
in
{
  imports = [
    (import ../../lib/mk-claim-kind.nix {
      name = "binds";
      description = ''
        Where the service accepts traffic, by bind id. A bind says where the
        service listens, never who may reach it.
      '';
      inherit conflict;
      claim =
        _:
        { config, lib, ... }:
        let
          inherit (libnet.withLib lib) types;
        in
        {
          options = {
            proto = lib.mkOption {
              type = lib.types.coercedTo types.transport (protocol: [ protocol ]) (
                lib.types.listOf types.transport
              );
              default = [ "tcp" ];
              description = ''
                The transport protocols the service listens on: one of `tcp`,
                `udp` and `sctp`, or a list of them.
              '';
            };
            port = lib.mkOption {
              type = lib.types.either types.port types.portRange;
              description = ''
                The port the service listens on, or a range written as
                `"<from>-<to>"`.
              '';
              example = 8086;
            };
            addresses = lib.mkOption {
              type = lib.types.coercedTo types.ip (address: [ address ]) (lib.types.listOf types.ip);
              default = [ "0.0.0.0" ];
              description = ''
                The addresses the service listens on. `0.0.0.0` and `::` listen
                on every address of their family.
              '';
              example = "127.0.0.1";
            };
            bindpoints = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              readOnly = true;
              default = map (
                address: "${if lib.hasInfix ":" address then "[${address}]" else address}:${toString config.port}"
              ) config.addresses;
              defaultText = lib.literalMD "`<address>:<port>` for each address";
              description = ''
                One `<address>:<port>` string per address, IPv6 addresses in
                brackets, for configuring the daemon.
              '';
            };
          };
        };
    })
  ];
}
