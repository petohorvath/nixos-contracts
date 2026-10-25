# Publishes what this node sends, for the inboxes of every node to read
# through the node collection, and checks each send on this node. Under
# `contracts.checkSends`, it publishes the sends of a second evaluation in
# which no inbox received anything, and checks they are its own.
{
  config,
  extendModules,
  lib,
  ...
}:
let
  references = import ./references.nix;
  inherit (references) labelOf locationLabelOf;
  inherit (config.contracts) checkSends;
  inherit (config.contracts.internal) collecting;

  # The sends of a configuration's contracts, `{ ref; location; to; }` per
  # claim and inbox it names, read from its claim sets alone: those of
  # enabled contracts, of every kind but inboxes, which are sent nowhere.
  sendsOf =
    contracts:
    lib.concatMap (
      kind:
      lib.concatMap (
        claim:
        map (to: {
          inherit (claim) ref location;
          inherit to;
        }) claim.sendTo
      ) (references.claimsOf contracts.claimSets.${kind})
    ) (lib.remove "inboxes" (lib.attrNames contracts.claimSets));

  sends = sendsOf config.contracts;

  # The sends of this configuration evaluated again with every inbox empty.
  # Nothing they depend on is received, so reading them never recurses.
  collectedSends =
    sendsOf
      (extendModules { modules = [ { contracts.internal.collecting = true; } ]; }).config.contracts;

  # The labels of the inboxes each claim sends to, sorted, by the claim.
  inboxesByClaim =
    sends:
    lib.mapAttrs (
      _: claimSends: lib.sort lib.lessThan (lib.unique (map (send: labelOf send.to) claimSends))
    ) (lib.groupBy (send: "${send.ref.kind} claim `${locationLabelOf send.location}`") sends);

  # One check per claim of either evaluation, failing when the claim sends
  # to other inboxes once its node has received claims than before.
  driftAssertions =
    let
      after = inboxesByClaim sends;
      before = inboxesByClaim collectedSends;
      describe =
        inboxes:
        if inboxes == [ ] then "nothing" else lib.concatMapStringsSep ", " (inbox: "`${inbox}`") inboxes;
    in
    map (
      claim:
      let
        inboxesAfter = after.${claim} or [ ];
        inboxesBefore = before.${claim} or [ ];
      in
      {
        assertion = inboxesAfter == inboxesBefore;
        message = "${claim} sends to ${describe inboxesAfter} once its node has received claims, but to ${describe inboxesBefore} before: whether a claim exists and where it is sent must not depend on an inbox's `received` or `refs`.";
      }
    ) (lib.unique (lib.attrNames after ++ lib.attrNames before));

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
  options.contracts = {
    checkSends = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to check that what this node sends does not depend on what
        its inboxes received, failing a check that names each claim that
        does, where such a send otherwise recurses without a message. The
        node is evaluated a second time, with every inbox empty, and the
        inboxes of every node read its sends from there.
      '';
    };

    internal.collecting = lib.mkOption {
      type = lib.types.bool;
      internal = true;
      default = false;
      description = ''
        Whether this is the evaluation `contracts.checkSends` reads the
        sends from, in which every inbox's `received` is empty.
      '';
    };

    internal.sends = lib.mkOption {
      # Lazy, so a node reading what another node sends it forces no other
      # node's entry. `attrsOf` would force only each entry's list, which
      # `groupBy` builds with the keys, so it would not recurse either and
      # no test tells them apart.
      type = lib.types.lazyAttrsOf lib.types.raw;
      internal = true;
      readOnly = true;
      default = lib.groupBy (send: send.to.node) (
        lib.filter (send: send.to.node != null) (
          if checkSends && !collecting then collectedSends else sends
        )
      );
      defaultText = lib.literalMD ''
        the sends of this configuration's claim sets, by receiving node, read
        from the evaluation with empty inboxes under `contracts.checkSends`
      '';
      description = ''
        What this configuration sends, by the receiving node's identity: a
        list of `{ ref; location; to; }` per node. A send naming no node is
        only checked.
      '';
    };
  };

  config.contracts.assertions =
    map sendAssertion sends ++ lib.optionals (checkSends && !collecting) driftAssertions;
}
