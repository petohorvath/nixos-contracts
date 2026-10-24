/**
  Option types of the contract vocabulary, for service modules whose own
  settings carry a value into a claim, such as a reference into a secret's
  `from`.
*/
{ lib }:
{
  /**
    A reference to a secret its value comes from: `{ node; name; }`, with
    the name of the node holding the secret in the node collection, or null
    for this configuration, and the secret's claim name. A claim name alone
    coerces to a reference with a null node.

    # Example

    ```nix
    options.writers = lib.mkOption {
      type = lib.types.attrsOf contractsLib.types.reference;
    };
    ```
  */
  reference = lib.types.coercedTo lib.types.str (name: { inherit name; }) (
    lib.types.submodule {
      options = {
        node = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            The node holding the secret, by its name in the node
            collection, or null for this configuration.
          '';
        };
        name = lib.mkOption {
          type = lib.types.str;
          description = "The secret's claim name, `<service>-<id>`.";
        };
      };
    }
  );
}
