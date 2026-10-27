# The arguments of `mkClaimKind` for binds: where a service accepts traffic.
{ lib, libnet }:
let
  netLib = libnet.withLib lib;
  inherit (netLib) ip port portRange;
  netTypes = netLib.types;

  toPortRange =
    value:
    if builtins.isInt value then portRange.fromPort (port.fromInt value) else portRange.parse value;

  # `0.0.0.0` covers every IPv4 address; `::` covers both families, since an
  # IPv6 wildcard socket on Linux accepts IPv4 unless the daemon sets
  # `IPV6_V6ONLY` (`net.ipv6.bindv6only` defaults to 0).
  covers =
    wildcard: address:
    ip.isUnspecified wildcard && (ip.version wildcard == 6 || ip.version address == 4);

  addressesOverlap =
    first: second:
    let
      firstAddress = ip.parse first;
      secondAddress = ip.parse second;
    in
    ip.eq firstAddress secondAddress
    || covers firstAddress secondAddress
    || covers secondAddress firstAddress;

  clash =
    first: second:
    let
      sharedProtocols = lib.intersectLists first.protocols second.protocols;
      addressPairs = lib.filter (pair: addressesOverlap pair.first pair.second) (
        lib.cartesianProduct {
          first = first.addresses;
          second = second.addresses;
        }
      );
    in
    if
      sharedProtocols != [ ]
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
      "both listen on ${lib.concatStringsSep "/" sharedProtocols} ${ports}, at `${pair.first}` and `${pair.second}`"
    else
      null;
in
{
  name = "binds";
  description = ''
    Where the service accepts traffic, by bind id. A bind says where the
    service listens, never who may reach it.
  '';
  inherit clash;
  claim =
    _:
    { config, ... }:
    {
      options = {
        protocols = lib.mkOption {
          type = lib.types.coercedTo netTypes.transport (protocol: [ protocol ]) (
            lib.types.listOf netTypes.transport
          );
          default = [ "tcp" ];
          description = ''
            The transport protocols the service listens on: one of `tcp`,
            `udp` and `sctp`, or a list of them.
          '';
        };
        port = lib.mkOption {
          type = lib.types.either netTypes.port netTypes.portRange;
          description = ''
            The port the service listens on, or a range written as
            `"<from>-<to>"`.
          '';
          example = 8086;
        };
        addresses = lib.mkOption {
          type = lib.types.coercedTo netTypes.ip (address: [ address ]) (lib.types.listOf netTypes.ip);
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
}
