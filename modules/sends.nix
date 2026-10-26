# Publishes what this node sends, for the inboxes of every node to read
# through the node collection, and checks each send on this node.
{ config, lib, ... }:
let
  references = import ./references.nix;
  inherit (references) labelOf locationLabelOf;

  # The sends of this configuration, `{ ref; location; to; }` per claim and
  # inbox it names, read from its claim sets alone: those of enabled
  # contracts, of every sendable kind.
  sends =
    lib.concatMap
      (
        kind:
        lib.concatMap (
          claim:
          map (to: {
            inherit (claim) ref location;
            inherit to;
          }) claim.sendTo
        ) (references.claimsOf config.contracts.claimSets.${kind})
      )
      (
        lib.filter (kind: config.contracts.internal.kinds.${kind}.sendable) (
          lib.attrNames config.contracts.claimSets
        )
      );

  # Each send's inbox exists on its node, in an enabled contract, and takes
  # the sent claim's kind.
  sendAssertion =
    send:
    let
      result = config.contracts.lookup send.to;
      sent = "${send.ref.kind} claim `${locationLabelOf send.location}` sends to `${labelOf send.to}`";
    in
    if result.reason != null then
      {
        assertion = false;
        message = "${sent}: ${result.reason}.";
      }
    else
      {
        assertion = result.claim.kind == send.ref.kind;
        message = "${sent}, which takes `${result.claim.kind}`, not `${send.ref.kind}`.";
      };
in
{
  options.contracts.internal.sends = lib.mkOption {
    # Lazy, so a node reading what another node sends it forces no other
    # node's entry. `attrsOf` would force only each entry's list, which
    # `groupBy` builds with the keys, so it would not recurse either and no
    # test tells them apart.
    type = lib.types.lazyAttrsOf lib.types.raw;
    internal = true;
    readOnly = true;
    default = lib.groupBy (send: send.to.node) (lib.filter (send: send.to.node != null) sends);
    defaultText = lib.literalMD "the sends of this configuration's claim sets, by receiving node";
    description = ''
      What this configuration sends, by the receiving node's identity: a
      list of `{ ref; location; to; }` per node. A send naming no node is
      only checked.
    '';
  };

  config.contracts.assertions = map sendAssertion sends;
}
