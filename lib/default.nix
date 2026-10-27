/**
  Public library functions and types. Import this directory by path with a
  caller-owned nixpkgs library to use them without evaluating any flake
  inputs:

    contractsLib = import "${nixos-contracts}/lib" { inherit lib; };
*/
{ lib }:
let
  inherit (import ../modules/references.nix)
    backendNameOf
    claimLabelOf
    claimNameOf
    claimsOf
    referenceLabelOf
    ;
in
{
  /**
    The name `<service>_<id>` a backend adapter gives its entry for a
    claim, taking anything with `service` and `id`. A service module names a
    secret's backend entry with it, such as to set a provided secret's
    encrypted file when it is not at the backend's default.

    # Example

    ```nix
    age.secrets.${backendNameOf { service = "influxdb"; id = "admin-token"; }}.rekeyFile = ./admin-token.age;
    # sets age.secrets.influxdb_admin-token.rekeyFile
    ```
  */
  inherit backendNameOf;

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
    The claims of one kind's claim set, such as
    `config.contracts.claimSets.secrets`, in a list, by service and then
    id. An adapter installs each claim of its kind from it.

    # Example

    ```nix
    map (secret: secret.name) (claimsOf config.contracts.claimSets.secrets)
    # => [ "beta_secrets_influxdb_admin-token" "beta_secrets_telegraf_token" ]
    ```
  */
  inherit claimsOf;

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

  /**
    The labels check messages give a claim and a reference, so an
    adapter's messages read like the core's: `labels.claim` takes anything
    with `service` and `id` and returns `<service>.<id>`, and
    `labels.reference` takes a reference and returns
    `<node>:<kind>.<service>.<id>`.

    # Example

    ```nix
    labels.claim { service = "influxdb"; id = "admin-token"; }
    # => "influxdb.admin-token"
    labels.reference { node = "metrics"; kind = "secrets"; service = "telegraf"; id = "token"; }
    # => "metrics:secrets.telegraf.token"
    ```
  */
  labels = {
    claim = claimLabelOf;
    reference = referenceLabelOf;
  };

  mkClaimKind = import ../modules/mk-claim-kind.nix;
  mkDefaultContract = import ./mk-default-contract.nix { inherit lib; };
  types = import ../modules/types.nix { inherit lib; };
}
