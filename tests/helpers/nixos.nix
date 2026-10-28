/*
  Evaluate NixOS configurations without building them. `evaluate` returns the
  `config` of a node named `local`, unless a module names another, and
  `evaluateWithoutNode` that of a configuration with no node identity.
  `failures` reads this library's failed checks, since NixOS's own
  assertions fail without a bootloader, and `optionsOf` returns the options
  of a node named `local`. `nixosModules` holds the library's NixOS modules
  by export name, `backends` the adapters' backend modules by input name, and
  `agenixRekeyBackends` the two the agenix-rekey adapter needs, for the
  suites to list.
*/
{
  backends,
  nixosModules,
  nixpkgs,
  system,
}:
let
  inherit (nixpkgs) lib;
  nixosSystemOf =
    modules:
    lib.nixosSystem {
      modules = [
        {
          nixpkgs.hostPlatform = system;
          system.stateVersion = "26.05";
        }
      ]
      ++ modules;
    };
  withNode = modules: [ { contracts.node = lib.mkDefault "local"; } ] ++ modules;
in
rec {
  inherit backends nixosModules;
  agenixRekeyBackends = [
    backends.agenix
    backends.agenix-rekey
  ];
  evaluateWithoutNode = modules: (nixosSystemOf modules).config;
  evaluate = modules: evaluateWithoutNode (withNode modules);
  failures = modules: (evaluate modules).contracts.failures;
  optionsOf = modules: (nixosSystemOf (withNode modules)).options;
}
