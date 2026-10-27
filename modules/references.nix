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

  # How messages name a name, by what it names, so the claim constructor,
  # the core and a reference's checks name it alike.
  describeName = {
    node = node: "node identity `${node}`";
    kind = kind: "claim kind name `${kind}`";
    service = service: "service name `${service}`";
    id =
      kind: service: id:
      "${kind} claim id `${id}` of service `${service}`";
  };

  # Why `name` breaks `rule`, one of `nameRules`, naming it as
  # `describe name` does, or null when it is non-empty and follows it.
  nameProblemOf =
    rule: describe: name:
    if builtins.match rule.pattern name != null then
      null
    else
      "${describe name} may contain only ${rule.allowed}";

  # `name` when it follows `rule`, failing with its problem otherwise.
  checkName =
    rule: describe: name:
    let
      problem = nameProblemOf rule describe name;
    in
    if problem == null then name else throw "nixos-contracts: ${problem}.";

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

  # The fields of a reference, each a string.
  referenceFields = [
    "node"
    "kind"
    "service"
    "id"
  ];

  # A reference as messages name it, `?` standing for a field it lacks or
  # that is not a string, so even a malformed reference can be named.
  partialReferenceLabelOf =
    reference:
    referenceLabelOf (
      builtins.listToAttrs (
        map (field: {
          name = field;
          value = if builtins.isString (reference.${field} or null) then reference.${field} else "?";
        }) referenceFields
      )
    );

  # `reference` when it is an attribute set with a string at each of
  # `referenceFields` and nothing else. Otherwise it fails, naming it.
  checkReferenceFields =
    reference:
    let
      fail =
        problem: throw "nixos-contracts: reference `${partialReferenceLabelOf reference}` ${problem}";
      missing = builtins.filter (field: !(reference ? ${field})) referenceFields;
      unknown = builtins.filter (field: !(builtins.elem field referenceFields)) (
        builtins.attrNames reference
      );
      notStrings = builtins.filter (field: !(builtins.isString reference.${field})) referenceFields;
    in
    if !(builtins.isAttrs reference) then
      throw "nixos-contracts: a reference is an attribute set `{ node; kind; service; id; }`, not a ${builtins.typeOf reference}"
    else if missing != [ ] then
      fail "has no `${builtins.head missing}`"
    else if unknown != [ ] then
      fail "has an unknown field `${builtins.head unknown}`"
    else if notStrings != [ ] then
      fail "has a `${builtins.head notStrings}` that is not a string"
    else
      reference;

  # Why a reference with every field names no claim of any node: the
  # first of its node identity, kind name, service name and id that breaks
  # its name rule, as the claim constructor names it, or null.
  referenceNameProblemOf =
    reference:
    let
      problems = builtins.filter (problem: problem != null) [
        (nameProblemOf nameRules.node describeName.node reference.node)
        (nameProblemOf nameRules.kind describeName.kind reference.kind)
        (nameProblemOf nameRules.service describeName.service reference.service)
        (nameProblemOf nameRules.id (describeName.id reference.kind reference.service) reference.id)
      ];
    in
    if problems == [ ] then null else builtins.head problems;

  # The reference to the claim of kind `kind` that `fields`,
  # `{ node; service; id; }`, name, failing, naming it, when it is malformed.
  mkReference =
    kind: fields:
    let
      reference = checkReferenceFields (
        if !(builtins.isAttrs fields) then
          fields
        else if fields ? kind then
          throw "nixos-contracts: reference `${
            partialReferenceLabelOf (fields // { inherit kind; })
          }` has an unknown field `kind`: `mkReference` takes the kind as its first argument"
        else
          fields // { inherit kind; }
      );
      problem = referenceNameProblemOf reference;
    in
    if problem == null then
      reference
    else
      throw "nixos-contracts: reference `${referenceLabelOf reference}`: ${problem}.";

  /*
    `{ claim; config; reason; }`: the claim-set entry a reference names, the
    configuration of the node that holds it and a null reason, or why the
    reference names no claim. Reading `claim` or `config` then fails with
    the reason; reading `reason` never does, but a reference missing a
    field or holding an unknown one fails on resolving, since it cannot be
    named.
  */
  resolve =
    config: unchecked:
    let
      reference = checkReferenceFields unchecked;
      nameProblem = referenceNameProblemOf reference;
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
    if nameProblem != null then
      fail nameProblem
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
        config = nodeConfig;
        reason = null;
      };
}
