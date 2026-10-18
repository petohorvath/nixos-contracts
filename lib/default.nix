/**
  Public library functions. Import this directory by path with a caller-owned
  nixpkgs library to use them without evaluating any flake inputs:

    contractsLib = import "${nixos-contracts}/lib" { inherit lib; };
*/
{ lib }:
{
  mkClaimKind = import ./mk-claim-kind.nix;
  mkDefaultContract = import ./mk-default-contract.nix { inherit lib; };
}
