# Evaluate NixOS configurations without building them. `failures` reads this
# library's failed checks, since NixOS's own assertions fail without a
# bootloader.
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
  failures = modules: (evaluate modules).contracts.failures;
}
