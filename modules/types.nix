/**
  Option types of the contract vocabulary, for service modules whose own
  settings carry a value into a claim, such as a reference into a secret's
  `value.copied`, and for claim kinds whose fields hold one of several cases.
*/
{ lib }:
let
  requiredString =
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
            requiredString "The claim's kind, such as `secrets`."
          else
            lib.mkOption {
              type = lib.types.enum [ kind ];
              default = kind;
              description = "The claim's kind, which must be `${kind}`.";
            };
        service = requiredString "The claim's service.";
        id = requiredString "The claim's id within its contract.";
      };
    };

  # The strongest (lowest) of some priorities, where null stands for none
  # and is weaker than any.
  strongestOf = lib.foldl' (
    strongest: priority:
    if strongest == null then
      priority
    else if priority == null then
      strongest
    else
      lib.min strongest priority
  ) null;

  /*
    The priority of a tag definition: the strongest of its leaves, each at
    the priority of its innermost override, or of a plain definition when
    none wraps it. A leaf under a false `lib.mkIf` has none, so a
    definition with no leaf left is weaker than any other.
  */
  definitionPriority =
    let
      # The priority of `value`, given the priority of the innermost
      # override around it.
      priorityWithin =
        enclosing: value:
        if value._type or null == "override" then
          priorityWithin value.priority value.content
        else if value._type or null == "if" then
          if value.condition then priorityWithin enclosing value.content else null
        else if value._type or null == "merge" then
          if value.contents == [ ] then
            enclosing
          else
            strongestOf (map (priorityWithin enclosing) value.contents)
        else if lib.isAttrs value && value != { } && !(lib.isDerivation value) then
          strongestOf (map (priorityWithin enclosing) (lib.attrValues value))
        else
          enclosing;
    in
    priorityWithin lib.modules.defaultOverridePriority;

  # The definitions of every tag whose strongest definition is the strongest
  # of all, so a conflict at that priority still reaches `attrTag`.
  strongestTagDefinitions =
    defs:
    let
      definitionsByTag = lib.groupBy (def: builtins.head (builtins.attrNames def.value)) defs;
      tagPriority = tagDefs: strongestOf (map (def: definitionPriority def.value) tagDefs);
      strongestPriority = strongestOf (map tagPriority (lib.attrValues definitionsByTag));
    in
    lib.concatLists (
      lib.attrValues (
        lib.filterAttrs (_: tagDefs: tagPriority tagDefs == strongestPriority) definitionsByTag
      )
    );

  /**
    A tag: an option that holds exactly one of several cases, like
    `lib.types.attrTag`, whose definitions settle by priority. When
    definitions name different tags, the tag whose strongest definition is
    strongest wins and the others' definitions are dropped, so a tag a
    module writes through `mkDefaultContract` gives way to another tag a
    node writes at normal priority. Two different tags at one priority
    still fail, naming the option.

    A definition counts at the priority of its strongest leaf, each leaf at
    the priority of its innermost `lib.mkOverride`, or the normal priority
    when none wraps it. `lib.mkIf` passes the priority through to its
    content when its condition is true and contributes none when it is
    false; `lib.mkMerge` takes the strongest of its contents.

    # Inputs

    `tags`
    : The tag declarations, an attribute set of options as
      `lib.types.attrTag` takes them.

    # Output

    An option type.

    # Example

    ```nix
    options.target = lib.mkOption {
      type = contractsLib.types.tag {
        local = lib.mkOption { type = lib.types.str; };
        remote = lib.mkOption { type = lib.types.str; };
      };
    };
    ```
  */
  tag =
    tags:
    let
      base = lib.types.attrTag tags;
    in
    base
    // {
      name = "tag";
      merge = loc: defs: base.merge loc (strongestTagDefinitions defs);
      # The module system rebuilds a type whose cases are submodules, so the
      # rebuilt `attrTag` is wrapped again.
      substSubModules = modules: tag (base.substSubModules modules).functor.payload.tags;
      functor = base.functor // {
        type = { tags, ... }: tag tags;
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
  referenceTo =
    kind:
    if builtins.isString kind then
      mkReference kind
    else
      throw "nixos-contracts: `types.referenceTo` takes a kind's name; use `types.reference` for any kind";

  inherit tag;
}
