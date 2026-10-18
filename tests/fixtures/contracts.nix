# Evaluate contract modules outside NixOS. `evaluate` returns the top-level
# `config`, and `failures` the messages of its failed assertions, so tests
# check clashes without a NixOS evaluation.
{ lib, module }:
rec {
  evaluate = modules: (lib.evalModules { modules = [ module ] ++ modules; }).config;
  failures =
    modules:
    lib.pipe (evaluate modules).contracts.assertions [
      (lib.filter (check: !check.assertion))
      (map (check: check.message))
    ];
}
