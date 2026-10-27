/*
  Evaluate NixOS configurations without building them. `evaluate` returns the
  `config` of a node named `local`, unless a module names another, and
  `evaluateWithoutNode` that of a configuration with no node identity.
  `failures` reads this library's failed checks, since NixOS's own
  assertions fail without a bootloader.
*/
{ nixpkgs, system }:
let
  inherit (nixpkgs) lib;
in
rec {
  evaluateWithoutNode =
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
  evaluate =
    modules: evaluateWithoutNode ([ { contracts.node = lib.mkDefault "local"; } ] ++ modules);
  failures = modules: (evaluate modules).contracts.failures;
}
