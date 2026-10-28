# The generic module: the core and the shipped claim kinds, for any module
# class.
{ libnet }:
{ lib, ... }:
let
  mkClaimKind = import ./mk-claim-kind.nix;

  # Builds the kind a file defines, declaring its options at that file.
  mkKindModule =
    path: arguments: lib.setDefaultModuleLocation path (mkClaimKind (import path arguments));

  kinds = [
    (mkKindModule ./kinds/binds.nix { inherit lib libnet; })
    (mkKindModule ./kinds/mounts.nix { inherit lib; })
    (mkKindModule ./kinds/secrets.nix { inherit lib; })
  ];
in
{
  # A caller applies this file to `{ libnet }`, so the module system gets
  # no path to name or identify the module by. `_file` names it in
  # diagnostics, and `key` keeps one copy, with its claim kinds, when
  # several modules import it.
  _file = ./default.nix;
  key = ./default.nix;

  imports = [ ./core.nix ] ++ kinds;
}
