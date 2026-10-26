# How a claim is named and placed, how a claim set's claims are listed,
# and how a reference `{ node; kind; service; id; }` reads its node and
# claim, shared by the core's `contracts.lookup`, the claim kinds and the
# adapters.
rec {
  /*
    What a name may contain, by what it names. A claim id may also contain
    `_`, a service name or node identity may not, so the first `_` of a
    backend name `<service>_<id>` ends the service, and the first two of a
    claim name `<node>_<service>_<id>` end the node and the service.
  */
  nameRules =
    let
      lowercaseDigitsAndHyphens = {
        pattern = "[a-z0-9-]+";
        allowed = "lowercase letters, digits and hyphens";
      };
    in
    {
      service = lowercaseDigitsAndHyphens;
      node = lowercaseDigitsAndHyphens;
      id = {
        pattern = "[a-z0-9_-]+";
        allowed = "lowercase letters, digits, hyphens and `_`";
      };
    };

  # `name` when it is non-empty and follows `rule`, one of `nameRules`.
  # Otherwise it fails, naming it as `describe name` does.
  checkName =
    rule: describe: name:
    if builtins.match rule.pattern name != null then
      name
    else
      throw "nixos-contracts: ${describe name} may contain only ${rule.allowed}.";

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
  # `influxdb_admin-token`. No service name contains `_`, so the first `_`
  # ends the service, and no two claims of a node make one name.
  backendNameOf = builtins.concatStringsSep "_";

  # Where the secret backend `backend` installs the secret at `location`,
  # failing, naming the secret, while no backend adapter sets it.
  backendPathOf =
    backend: location:
    if backend == null then
      throw "nixos-contracts: secret `${locationLabelOf location}` has no path: import a secret backend adapter such as `nixosModules.agenix-rekey`, which sets `contracts.kinds.secrets.backend`"
    else
      backend.path location;

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
