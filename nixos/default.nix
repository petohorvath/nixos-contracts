/*
  The NixOS modules by export name: `default` is the generic module with its
  checks as NixOS assertions, and each adapter imports `default` beside its
  own file. Importing `default` several times is safe, since the module
  system imports the generic module, by its key, and each file once.
*/
{ libnet }:
let
  generic = import ../modules { inherit libnet; };
  default.imports = [
    generic
    ./assertions.nix
  ];
  withDefault = adapter: {
    imports = [
      default
      adapter
    ];
  };
in
{
  inherit default;
  agenix-rekey = withDefault ./adapters/agenix-rekey.nix;
  preservation = withDefault ./adapters/preservation.nix;
  systemd-credentials = withDefault ./adapters/systemd-credentials.nix;
}
