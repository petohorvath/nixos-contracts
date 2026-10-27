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
  /*
    An adapter with the default module. Each adapter file is a function of
    the public library, `contractsLib`, returning its module, so it uses
    nothing a project's own adapter cannot. The key keeps one copy of an
    adapter imported twice.
  */
  withDefault = file: {
    imports = [
      default
      (
        { lib, ... }:
        let
          contractsLib = import ../lib { inherit lib; };
        in
        {
          _file = file;
          key = toString file;
          imports = [ (import file contractsLib) ];
        }
      )
    ];
  };
in
{
  inherit default;
  agenix-rekey = withDefault ./adapters/agenix-rekey.nix;
  preservation = withDefault ./adapters/preservation.nix;
  systemd-credentials = withDefault ./adapters/systemd-credentials.nix;
}
