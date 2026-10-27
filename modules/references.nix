# How a claim is named, how a claim set's claims are listed, and how a
# reference `{ node; kind; service; id; }` reads its node and claim, shared
# by the core's `contracts.resolve`, the claim kinds and the adapters.
rec {
  /*
    What a name may contain, by what it names. A claim id may also contain
    `_`, a node identity, kind name or service name may not, so the first
    `_` of a backend name `<service>_<id>` ends the service, and the first
    three of a claim name `<node>_<kind>_<service>_<id>` end the node, the
    kind and the service.
  */
  nameRules =
    let
      lowercaseDigitsAndHyphens = {
        pattern = "[a-z0-9-]+";
        allowed = "lowercase letters, digits and hyphens";
      };
    in
    {
      node = lowercaseDigitsAndHyphens;
      kind = lowercaseDigitsAndHyphens;
      service = lowercaseDigitsAndHyphens;
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
  # null for a node missing from it.
  nodeConfigOrNull =
    config: reference:
    if reference.node == config.contracts.node then
      config
    else
      config.contracts.nodes.${reference.node}.config or null;

  # A claim's name, `<node>_<kind>_<service>_<id>`, such as
  # `metrics_secrets_telegraf_token`, from its reference alone, so naming
  # a claim of another node reads none of that node's claim sets.
  claimNameOf =
    {
      node,
      kind,
      service,
      id,
      ...
    }:
    "${node}_${kind}_${service}_${id}";

  # A claim as messages name it, `<service>.<id>`, such as
  # `influxdb.admin-token`.
  claimLabelOf = { service, id, ... }: "${service}.${id}";

  # The name a backend adapter gives its entry for a claim, `<service>_<id>`,
  # such as `influxdb_admin-token`. No service name contains `_`, so the
  # first `_` ends the service, and no two claims of a node make one name.
  backendNameOf = { service, id, ... }: "${service}_${id}";

  # Where the secret backend `backend` installs the secret `secret`, failing,
  # naming the secret, while no backend adapter sets it.
  backendPathOf =
    backend: secret:
    if backend == null then
      throw "nixos-contracts: secret `${claimLabelOf secret}` has no path: import a secret backend adapter such as `nixosModules.agenix-rekey`, which sets `contracts.kinds.secrets.backend`"
    else
      backend.path { inherit (secret) service id; };

  # Where the delivery `delivery` hands the secret `secret` to its unit,
  # failing, naming the secret, while no delivery adapter sets it.
  deliveryPathOf =
    delivery: secret:
    if delivery == null then
      throw "nixos-contracts: secret `${claimLabelOf secret}` is delivered to `${secret.unit}` but has no path: import a delivery adapter such as `nixosModules.systemd-credentials`, which sets `contracts.kinds.secrets.delivery`, or set its `unit` to null"
    else
      delivery.path { inherit (secret) unit service id; };

  # The claims of a claim set, by service and then id, in a list.
  claimsOf = claimSet: builtins.concatMap builtins.attrValues (builtins.attrValues claimSet);

  # A reference as messages name it.
  referenceLabelOf =
    reference: "${reference.node}:${reference.kind}.${reference.service}.${reference.id}";

  /*
    `{ claim; config; reason; }`: the claim-set entry a reference names, the
    configuration of the node that holds it and a null reason, or why the
    reference names no claim. Reading `claim` or `config` then fails with
    the reason; reading `reason` never does.
  */
  resolve =
    config: reference:
    let
      nodeConfig = nodeConfigOrNull config reference;
      claimSets = nodeConfig.contracts.claimSets;
      entry = claimSets.${reference.kind}.${reference.service}.${reference.id} or null;
      fail =
        reason:
        let
          error = throw "nixos-contracts: cannot resolve `${referenceLabelOf reference}`: ${reason}";
        in
        {
          claim = error;
          config = error;
          inherit reason;
        };
    in
    if nodeConfig == null then
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
        config = nodeConfig;
        reason = null;
      };
}
