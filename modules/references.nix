# How a reference `{ node; kind; service; id; }` reads its node and claim,
# shared by the core's `contracts.lookup`, the secrets kind and backend
# adapters.
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
    reference: "${toString reference.node}:${reference.kind}.${reference.service}.${reference.id}";

  # `{ claim; reason; }`: the claim-set entry a reference names, or a null
  # claim and why it does not resolve.
  lookup =
    config: reference:
    let
      nodeConfig = nodeConfigOrNull config reference;
      claimName = "${reference.service}-${reference.id}";
      claimSets = nodeConfig.contracts.claimSets;
      entry = claimSets.${reference.kind}.${claimName} or null;
      fail = reason: {
        claim = null;
        inherit reason;
      };
    in
    # A claim's `ref` names no node while its configuration has no node
    # identity; it must not resolve as this configuration's claim.
    if reference.node == null then
      fail "it names no node, since the configuration holding the claim sets no `contracts.node`"
    else if nodeConfig == null then
      fail "node `${reference.node}` is not in `contracts.nodes`"
    else if !(nodeConfig ? contracts.claimSets) then
      fail "node `${reference.node}` imports no nixos-contracts module"
    else if !(claimSets ? ${reference.kind}) then
      fail "node `${reference.node}` has no claim kind `${reference.kind}`"
    # The service and id guard against a claim name that another split of
    # `<service>-<id>` produces.
    else if entry == null || entry.service != reference.service || entry.id != reference.id then
      fail "no enabled contract on `${reference.node}` holds it"
    else
      {
        claim = entry;
        reason = null;
      };
}
