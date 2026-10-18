# Evaluate NixOS configurations without building them. `failures` keeps only
# this library's failed assertions, since NixOS's own fail without a bootloader.
{ nixpkgs, system }:
let
  inherit (nixpkgs) lib;
in
rec {
  evaluate =
    modules:
    (lib.nixosSystem {
      modules = [
        {
          nixpkgs.hostPlatform = system;
          system.stateVersion = "26.05";
        }
      ]
      ++ modules;
    }).config;
  failures =
    modules:
    lib.pipe (evaluate modules).assertions [
      (lib.filter (check: !check.assertion))
      (map (check: check.message))
      (lib.filter (lib.hasPrefix "nixos-contracts: "))
    ];
}
