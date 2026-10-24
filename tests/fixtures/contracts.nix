# Evaluate contract modules outside NixOS. `evaluate` returns the top-level
# `config`, `failures` the messages of its failed checks, so tests check
# clashes without a NixOS evaluation, and `nodesOf` configurations by node
# name sharing one node collection.
{ lib, module }:
rec {
  evaluate = modules: (lib.evalModules { modules = [ module ] ++ modules; }).config;
  failures = modules: (evaluate modules).contracts.failures;
  nodesOf = import ./nodes.nix { inherit evaluate; };
}
