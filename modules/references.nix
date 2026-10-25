# How a claim is named and placed, and how a reference
# `{ node; kind; service; id; }` reads its node and claim, shared by the
# core's `contracts.lookup`, the claim kinds and the adapters.
rec {
  /*
    `name` when it is a name, as service names, claim ids and node
    identities must be: non-empty, of lowercase letters, digits and hyphens
    only. Otherwise it fails, naming it as `describe name` does.
  */
  checkName =
    describe: name:
    if builtins.match "[a-z0-9-]+" name != null then
      name
    else
      throw "nixos-contracts: ${describe name} may contain only lowercase letters, digits and hyphens.";

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

  # A claim's location as messages name it, such as `influxdb.admin-token`.
  locationLabelOf = builtins.concatStringsSep ".";

  # The name a backend adapter gives its entry for a claim, such as
  # `influxdb_admin-token`. No name of a location contains `_`, so no two
  # locations make one name.
  backendNameOf = builtins.concatStringsSep "_";

  # The claims of a claim set, by service and then id, in a list.
  claimsOf = claimSet: builtins.concatMap builtins.attrValues (builtins.attrValues claimSet);

  # A reference as messages name it.
  labelOf =
    reference:
    "${
      if reference.node == null then "<no node>" else reference.node
    }:${reference.kind}.${reference.service}.${reference.id}";

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
    # A claim's `ref` names no node while its configuration has no node
    # identity; it must not resolve as this configuration's claim.
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
