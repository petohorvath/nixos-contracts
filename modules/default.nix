# The generic module: the core and the shipped claim kinds, for any module
# class.
{ libnet }:
{ lib, ... }:
let
  mkClaimKind = import ./mk-claim-kind.nix;

  # Builds the kind a file defines, declaring its options at that file.
  kindModule =
    path: arguments: lib.setDefaultModuleLocation path (mkClaimKind (import path arguments));

  kinds = [
    (kindModule ./kinds/binds.nix { inherit lib libnet; })
    (kindModule ./kinds/mounts.nix { inherit lib; })
    (kindModule ./kinds/secrets.nix { inherit lib; })
  ];
in
{
  # Identifies the module by its file, so it declares its options once
  # however often it is imported.
  key = toString ./default.nix;

  imports = [ ./core.nix ] ++ kinds;
}
