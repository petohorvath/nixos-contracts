/**
  The NixOS modules by export name: `default` is the generic module with its
  checks as NixOS assertions, and each other module imports `default`
  beside its own file. Import this directory by path with the nix-libnet
  library to use them without evaluating the flake's inputs:

    import "${nixos-contracts}/nixos" { libnet = nix-libnet.lib; }
*/
{ libnet }:
let
  generic = import ../modules { inherit libnet; };
  default.imports = [
    generic
    ./assertions.nix
  ];
  # An adapter, or the cross-config module, with the default module.
  withDefault = file: {
    imports = [
      default
      file
    ];
  };
in
{
  inherit default;
  agenix-rekey = withDefault ./adapters/agenix-rekey.nix;
  cross-config = withDefault ./cross-config.nix;
  preservation = withDefault ./adapters/preservation.nix;
  systemd-credentials = withDefault ./adapters/systemd-credentials.nix;
}
