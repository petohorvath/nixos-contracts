# PROTOTYPE (claim-inboxes): an attribute-tagged union whose definitions
# that name different tags are settled by priority. A definition's priority
# is the strongest override inside it, so a tag a module writes through
# `lib.mkDefaultContract`, which marks each leaf rather than the tag, still
# gives way to a tag a node writes at normal priority. Tags of one priority
# that differ still fail, as with `lib.types.attrTag`.
{ lib }:
let
  # The strongest (lowest) priority among a definition's leaves, each leaf
  # at the priority of the innermost override around it, or of a plain
  # definition when none is.
  strength =
    let
      go =
        inherited: value:
        if lib.isAttrs value && value ? _type then
          if value._type == "override" then
            go value.priority value.content
          else if value._type == "if" then
            go inherited value.content
          else if value._type == "merge" then
            lib.foldl' lib.min (if value.contents == [ ] then inherited else 1000000) (
              map (go inherited) value.contents
            )
          else
            inherited
        else if lib.isAttrs value && value != { } && !(lib.isDerivation value) then
          lib.foldl' lib.min 1000000 (map (go inherited) (lib.attrValues value))
        else
          inherited;
    in
    go lib.modules.defaultOverridePriority;

  tagOf = def: builtins.head (builtins.attrNames def.value);

  # The definitions of the strongest tag: every definition of a tag whose
  # strongest definition is the strongest of all.
  strongest =
    defs:
    let
      byTag = lib.groupBy tagOf defs;
      priorityOf = group: lib.foldl' lib.min 1000000 (map (def: strength def.value) group);
      best = lib.foldl' lib.min 1000000 (map priorityOf (lib.attrValues byTag));
    in
    lib.concatLists (lib.attrValues (lib.filterAttrs (_: group: priorityOf group == best) byTag));

  tag =
    tags:
    let
      base = lib.types.attrTag tags;
    in
    base
    // {
      name = "tag";
      merge = loc: defs: base.merge loc (strongest defs);
      substSubModules = modules: rewrap (base.substSubModules modules);
      functor = base.functor // {
        type = { tags, ... }: tag tags;
      };
    };

  # Re-wraps an attrTag the module system rebuilt for submodule definitions.
  rewrap = attrTag: tag (attrTag.functor.payload.tags or attrTag.nestedTypes);
in
tag
