# The generic module: the core and the shipped claim kinds, for any module
# class.
{ libnet }:
{ lib, ... }:
let
  mkClaimKind = import ./mk-claim-kind.nix;
  kinds = [
    (import ./kinds/binds.nix { inherit lib libnet; })
    (import ./kinds/mounts.nix { inherit lib; })
    (import ./kinds/secrets.nix { inherit lib; })
  ];
in
{
  # Identifies the module by its file, so it declares its options once when
  # several modules import it, as every NixOS adapter does.
  key = toString ./default.nix;

  imports = [ ./core.nix ] ++ map mkClaimKind kinds;
}
