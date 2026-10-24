/**
  Option types of the contract vocabulary, for service modules whose own
  settings carry a value into a claim, such as a reference into a secret's
  `from`.
*/
{ lib }:
let
  field =
    description:
    lib.mkOption {
      type = lib.types.str;
      inherit description;
    };

  # A reference as every claim's `ref` holds it. It names a node, so it
  # means the same claim on every node that reads it; only the `ref` of a
  # claim whose configuration has no node identity names null.
  mkReference =
    kind:
    lib.types.submodule {
      options = {
        node = lib.mkOption {
          # Not `nullOr`, whose undefined value is null: a reference written
          # without a node fails here rather than as a node-less claim.
          type = lib.types.either lib.types.str (lib.types.enum [ null ]);
          description = ''
            The node holding the claim, by its node identity, or null for a
            claim of a configuration without one, which no lookup resolves.
          '';
        };
        kind =
          if kind == null then
            field "The claim's kind, such as `secrets`."
          else
            lib.mkOption {
              type = lib.types.enum [ kind ];
              default = kind;
              description = "The claim's kind, which must be `${kind}`.";
            };
        service = field "The claim's service.";
        id = field "The claim's id within its contract.";
      };
    };
in
{
  /**
    A reference to a claim of any kind: `{ node; kind; service; id; }`.
  */
  reference = mkReference null;

  /**
    A reference to a claim of one kind: `{ node; service; id; }`, its
    `kind` defaulting to that kind and accepting no other.

    # Example

    ```nix
    options.backends = lib.mkOption {
      type = lib.types.attrsOf (contractsLib.types.referenceTo "binds");
    };
    ```
  */
  referenceTo = mkReference;
}
