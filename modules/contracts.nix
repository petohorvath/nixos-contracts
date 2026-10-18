# The core and the shipped claim kinds, for any module class.
{ libnet }:
{
  imports = [
    ./core.nix
    (import ./kinds/binds.nix { inherit libnet; })
    ./kinds/mounts.nix
    ./kinds/secrets.nix
  ];
}
