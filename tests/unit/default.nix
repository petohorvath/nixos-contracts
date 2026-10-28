# The unit suites: the library and the generic module under a bare
# `lib.evalModules`, which fails if the core reads a NixOS option.
{ nix-libnet, nixpkgs }:
let
  testContext = import ../test-context.nix { inherit nix-libnet nixpkgs; };
in
{
  custom-kind-example = import ./custom-kind-example.nix testContext;
  lib = import ./lib.nix testContext;
  mk-default-contract = import ./mk-default-contract.nix testContext;
  modules = {
    core = import ./modules/core.nix testContext;
    kinds = {
      binds = import ./modules/kinds/binds.nix testContext;
      mounts = import ./modules/kinds/mounts.nix testContext;
      secrets = import ./modules/kinds/secrets.nix testContext;
    };
    mk-claim-kind = import ./modules/mk-claim-kind.nix testContext;
    modules = import ./modules/modules.nix testContext;
    types = import ./modules/types.nix testContext;
  };
}
