# PROTOTYPE (claim-inboxes): claim sets are keyed by service and id, so a
# reference reads `claimSets.<kind>.<service>.<id>` and no string join can
# make two claims meet.
rec {
  # The configuration a reference reads: this configuration when the
  # reference names `contracts.node`, else the node collection's entry, or
  # null for a node missing from it or a reference that names no node.
  nodeConfigOrNull =
    config: reference:
    if reference.node == null then
      null
    else if reference.node == config.contracts.node then
      config
    else
      config.contracts.nodes.${reference.node}.config or null;

  # A reference as messages name it.
  labelOf =
    reference:
    "${
      if reference.node == null then "<no node>" else reference.node
    }:${reference.kind}.${reference.service}.${reference.id}";

  # A claim's address as messages name it.
  addressLabel = address: builtins.concatStringsSep "." address;

  # `{ claim; reason; }`: the claim-set entry a reference names, or a null
  # claim and why it does not resolve.
  lookup =
    config: reference:
    let
      nodeConfig = nodeConfigOrNull config reference;
      claimSets = nodeConfig.contracts.claimSets;
      entry = claimSets.${reference.kind}.${reference.service}.${reference.id} or null;
      fail = reason: {
        claim = null;
        inherit reason;
      };
    in
    if reference.node == null then
      fail "it names no node; a claim's `ref` names one only when its configuration sets `contracts.node`"
    else if nodeConfig == null then
      fail "node `${reference.node}` is not in `contracts.nodes`"
    else if !(nodeConfig ? contracts.claimSets) then
      fail "node `${reference.node}` imports no nixos-contracts module"
    else if !(claimSets ? ${reference.kind}) then
      fail "node `${reference.node}` has no claim kind `${reference.kind}`"
    else if entry == null then
      fail "no enabled contract on `${reference.node}` holds it"
    else
      {
        claim = entry;
        reason = null;
      };
}
