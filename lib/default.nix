/**
  Public library functions and types. Import this directory by path with a
  caller-owned nixpkgs library to use them without evaluating any flake
  inputs:

    contractsLib = import "${nixos-contracts}/lib" { inherit lib; };
*/
{ lib }:
let
  inherit (import ../modules/references.nix) claimNameOf;
in
{
  /**
    The claim name `<node>_<kind>_<service>_<id>` of the claim a reference
    names, built from the reference alone, without resolving it. A receiver
    keys the claims it builds from references with it, and reads no other
    node's claim set doing so.

    # Example

    ```nix
    claimNameOf { node = "metrics"; kind = "secrets"; service = "telegraf"; id = "token"; }
    # => "metrics_secrets_telegraf_token"
    ```
  */
  inherit claimNameOf;

  /**
    A copy of each referenced secret, keyed by its claim name, each with
    `value.copied` set to its reference, for a contract's `secrets`. Per-copy
    fields, such as an owner and mode, go in a second definition under the
    same keys, which the module system merges into each copy.

    # Example

    ```nix
    contracts.services.influxdb.secrets = lib.mkMerge [
      (copiesOf writers)
      (lib.genAttrs (map claimNameOf writers) (_: { mode = "0400"; }))
    ];
    ```
  */
  copiesOf =
    references:
    lib.listToAttrs (
      map (reference: lib.nameValuePair (claimNameOf reference) { value.copied = reference; }) references
    );

  mkClaimKind = import ../modules/mk-claim-kind.nix;
  mkDefaultContract = import ./mk-default-contract.nix { inherit lib; };
  types = import ../modules/types.nix { inherit lib; };
}
