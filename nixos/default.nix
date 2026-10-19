/**
  The NixOS modules by export name: `default` is the generic module with its
  checks as NixOS assertions, and each adapter imports `default` beside its
  own file. Import this directory by path with the nix-libnet library to use
  them without evaluating the flake's inputs:

    import "${nixos-contracts}/nixos" { libnet = nix-libnet.lib; }
*/
{ libnet }:
let
  generic = import ../modules { inherit libnet; };
  default.imports = [
    generic
    ./assertions.nix
  ];
  adapterModule = adapter: {
    imports = [
      default
      adapter
    ];
  };
in
{
  inherit default;
  agenix-rekey = adapterModule ./adapters/agenix-rekey.nix;
  preservation = adapterModule ./adapters/preservation.nix;
  systemd-credentials = adapterModule ./adapters/systemd-credentials.nix;
}
