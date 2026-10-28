# The integration suites: the NixOS modules, the adapters with their real
# backends and the NixOS examples in NixOS configurations, and the flake's
# outputs.
{
  agenix,
  agenix-rekey,
  nix-libnet,
  nixpkgs,
  preservation,
  self,
  system,
}:
let
  testContext = import ../test-context.nix {
    inherit
      agenix
      agenix-rekey
      nix-libnet
      nixpkgs
      preservation
      self
      system
      ;
  };
in
{
  agenix-rekey-adapter = import ./agenix-rekey-adapter.nix testContext;
  flake-outputs = import ./flake-outputs.nix testContext;
  nixos-examples = import ./nixos-examples.nix testContext;
  nixos-module = import ./nixos-module.nix testContext;
  preservation-adapter = import ./preservation-adapter.nix testContext;
  systemd-credentials-adapter = import ./systemd-credentials-adapter.nix testContext;
}
