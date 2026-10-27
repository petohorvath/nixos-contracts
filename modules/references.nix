# How a claim is named, how a claim set's claims are listed, and how a
# reference `{ node; kind; service; id; }` reads its node and claim, shared
# by the core's `contracts.resolve` and `contracts.resolveService`, the claim
# kinds and the adapters.
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

  # The fields of the service selection `{ node; kind; service; }` that
  # `contracts.resolveService` takes, each a string.
  serviceFields = [
    "node"
    "kind"
    "service"
  ];

  # A service selection as messages name it.
  serviceLabelOf = selection: "${selection.node}:${selection.kind}.${selection.service}";

  # `value` as `labelOf` names a value of `fields`, `?` standing for a field
  # it lacks or that is not a string, so even a malformed value can be named.
  partialLabelOf =
    fields: labelOf: value:
    labelOf (
      builtins.listToAttrs (
        map (field: {
          name = field;
          value = if builtins.isString (value.${field} or null) then value.${field} else "?";
        }) fields
      )
    );

  partialReferenceLabelOf = partialLabelOf referenceFields referenceLabelOf;

  # `value` when it is an attribute set with a string at each of `fields`
  # and nothing else. Otherwise it fails, naming it as `what` and `labelOf`
  # do, or saying it is not `shape` when it is not an attribute set.
  checkFields =
    {
      what,
      fields,
      labelOf,
      shape,
    }:
    value:
    let
      fail =
        problem: throw "nixos-contracts: ${what} `${partialLabelOf fields labelOf value}` ${problem}";
      missing = builtins.filter (field: !(value ? ${field})) fields;
      unknown = builtins.filter (field: !(builtins.elem field fields)) (builtins.attrNames value);
      notStrings = builtins.filter (field: !(builtins.isString value.${field})) fields;
    in
    if !(builtins.isAttrs value) then
      throw "nixos-contracts: ${shape} `{ ${
        builtins.concatStringsSep " " (map (field: "${field};") fields)
      } }`, not a ${builtins.typeOf value}"
    else if missing != [ ] then
      fail "has no `${builtins.head missing}`"
    else if unknown != [ ] then
      fail "has an unknown field `${builtins.head unknown}`"
    else if notStrings != [ ] then
      fail "has a `${builtins.head notStrings}` that is not a string"
    else
      value;

  # `reference` when it is an attribute set with a string at each of
  # `referenceFields` and nothing else. Otherwise it fails, naming it.
  checkReferenceFields = checkFields {
    what = "reference";
    fields = referenceFields;
    labelOf = referenceLabelOf;
    shape = "a reference is an attribute set";
  };

  # A service selection when it has a string at each of `serviceFields` and
  # nothing else. Otherwise it fails, naming it.
  checkServiceFields = checkFields {
    what = "service";
    fields = serviceFields;
    labelOf = serviceLabelOf;
    shape = "`contracts.resolveService` takes an attribute set";
  };

  # Why a value of `fields` names nothing on any node: the first of its
  # names that breaks its name rule, as the claim constructor names it, or
  # null.
  nameProblemOfFields =
    fields: value:
    let
      problemOf =
        field:
        if field == "id" then
          nameProblemOf nameRules.id (describeName.id value.kind value.service) value.id
        else
          nameProblemOf nameRules.${field} describeName.${field} value.${field};
      problems = builtins.filter (problem: problem != null) (map problemOf fields);
    in
    if problems == [ ] then null else builtins.head problems;

  # Why a reference with every field names no claim of any node: the
  # first of its node identity, kind name, service name and id that breaks
  # its name rule, as the claim constructor names it, or null.
  referenceNameProblemOf = nameProblemOfFields referenceFields;

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

  # The values of `fields`, each failing with the message
  # `nixos-contracts: cannot resolve <label>: <reason>`, and the reason.
  unresolved =
    label: fields: reason:
    let
      error = throw "nixos-contracts: cannot resolve ${label}: ${reason}";
    in
    builtins.listToAttrs (
      map (field: {
        name = field;
        value = error;
      }) fields
    )
    // {
      inherit reason;
    };

  # `{ config; claimSet; reason; }`: the configuration of the node a
  # reference or service names, its claim set of the named kind and a null
  # reason, or `{ reason; }`, why the node has no such claim set.
  claimSetOf =
    config:
    { node, kind, ... }@named:
    let
      nodeConfig = nodeConfigOrNull config named;
    in
    if nodeConfig == null then
      { reason = "node `${node}` is not in `contracts.nodes`"; }
    else if !(nodeConfig ? contracts.claimSets) then
      { reason = "node `${node}` imports no nixos-contracts module"; }
    else if !(nodeConfig.contracts.claimSets ? ${kind}) then
      { reason = "node `${node}` has no claim kind `${kind}`"; }
    else
      {
        config = nodeConfig;
        claimSet = nodeConfig.contracts.claimSets.${kind};
        reason = null;
      };

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
      found = claimSetOf config reference;
      entry = found.claimSet.${reference.service}.${reference.id} or null;
      fail = unresolved "`${referenceLabelOf reference}`" [
        "claim"
        "config"
      ];
    in
    if nameProblem != null then
      fail nameProblem
    else if found.reason != null then
      fail found.reason
    else if entry == null then
      fail "no enabled contract on `${reference.node}` holds it"
    else
      {
        claim = entry;
        inherit (found) config;
        reason = null;
      };

  /*
    `{ claims; config; reason; }`: the claims of one kind that a service
    holds on a node, as the selection `{ node; kind; service; }` names
    them, by id as the node's claim set holds them, that node's
    configuration and a null reason, or why no enabled contract on the node
    describes the service. An enabled contract without claims of the kind
    resolves to no claims. Reading `claims` or `config` then fails with the
    reason; reading `reason` never does, but a selection missing a field
    or holding an unknown one fails on resolving, since it cannot be named.
  */
  resolveService =
    config: unchecked:
    let
      selection = checkServiceFields unchecked;
      nameProblem = nameProblemOfFields serviceFields selection;
      found = claimSetOf config selection;
      enabled = found.config.contracts.services.${selection.service}.enable or false;
      fail = unresolved "service `${serviceLabelOf selection}`" [
        "claims"
        "config"
      ];
    in
    if nameProblem != null then
      fail nameProblem
    else if found.reason != null then
      fail found.reason
    else if !enabled then
      fail "no enabled contract on `${selection.node}` describes service `${selection.service}`"
    else
      {
        claims = found.claimSet.${selection.service} or { };
        inherit (found) config;
        reason = null;
      };
}
