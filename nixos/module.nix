# Contracts for a NixOS configuration, with their checks as NixOS assertions.
{ libnet }:
{ config, ... }:
{
  # Lets every adapter import this module without declaring its options twice.
  key = "nixos-contracts/nixos/module.nix";

  imports = [ (import ../modules/contracts.nix { inherit libnet; }) ];

  assertions = map (check: { inherit (check) assertion message; }) config.contracts.assertions;
}
