# Evaluate contract modules outside NixOS. `evaluate` returns the top-level
# `config`, and `failures` the messages of its failed checks, so tests check
# clashes without a NixOS evaluation.
{ lib, module }:
rec {
  evaluate = modules: (lib.evalModules { modules = [ module ] ++ modules; }).config;
  failures = modules: (evaluate modules).contracts.failures;
}
