# The arguments of `mkClaimKind` for inboxes: where claims of one kind
# arrive from any node, the node itself included, by their `sendTo`.
{ lib }:
let
  references = import ../references.nix;

  # Kinds whose received claims the receiving service can hold a copy of.
  copyKinds = [ "secrets" ];

  # Nests sends as `<node>.<service>.<id>` of what `f` makes of each,
  # keeping one of the sends of a claim that names the inbox twice.
  nest =
    f: sends:
    lib.mapAttrs (
      _: byNode:
      lib.mapAttrs (
        _: byService:
        lib.mapAttrs (_: sendsOfClaim: f (builtins.head sendsOfClaim)) (
          lib.groupBy (send: send.ref.id) byService
        )
      ) (lib.groupBy (send: send.ref.service) byNode)
    ) (lib.groupBy (send: send.ref.node) sends);

  # The entries of `received`, by node, service and then id, in a list.
  entriesOf = received: lib.concatMap references.claimsOf (lib.attrValues received);
in
{
  name = "inboxes";
  description = ''
    Inboxes of the service, by id: where claims of one kind arrive from
    any node, the node itself included, when they name the inbox in their
    `sendTo`.
  '';

  check =
    { claim, config, ... }:
    if claim.kind == "inboxes" then
      "it takes `inboxes`, which no claim can be sent as"
    else if !(config.contracts.claimSets ? ${claim.kind}) then
      "it takes `${claim.kind}`, which is no claim kind of this node"
    else if claim.copy != null && !builtins.elem claim.kind copyKinds then
      "it sets `copy`, but `${claim.kind}` claims have no copies; set `copy = null` and read `received`"
    else
      null;

  claim =
    { service, config, ... }:
    let
      topConfig = config;
      inherit (topConfig.contracts) node;
    in
    { name, config, ... }:
    let
      inbox = config;

      # What every node sends to this node: this configuration's own sends,
      # read from itself, and those of the other nodes of the collection.
      sendsHere = lib.concatMap (nodeConfig: nodeConfig.contracts.internal.sends.${node} or [ ]) (
        [ topConfig ]
        ++ map (entry: entry.config) (lib.attrValues (removeAttrs topConfig.contracts.nodes [ node ]))
      );

      # An inbox receives only while its node has an identity, which every
      # send names, and its contract is enabled, and never in the evaluation
      # `contracts.checkSends` collects the sends from.
      receives =
        node != null
        && topConfig.contracts.services.${service}.enable
        && !topConfig.contracts.internal.collecting;

      sends = lib.filter (
        send: send.to.service == service && send.to.id == name && send.ref.kind == inbox.kind
      ) sendsHere;
    in
    {
      options = {
        kind = lib.mkOption {
          type = lib.types.str;
          default = "secrets";
          description = "The claim kind the inbox takes.";
        };
        copy = lib.mkOption {
          type = lib.types.nullOr lib.types.deferredModule;
          default = null;
          description = ''
            Null to only receive references, or the settings of the copy the
            service holds of each secret it receives, such as its `mode`.
            Only an inbox of secrets holds copies.
          '';
        };
        received = lib.mkOption {
          type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw));
          readOnly = true;
          default = lib.optionalAttrs receives (
            nest (send: {
              inherit (send) ref;
              # The sent claim as its node's claim set holds it.
              inherit ((topConfig.contracts.lookup send.ref)) claim;
              copy = null;
            }) sends
          );
          defaultText = lib.literalMD "the claims sent here, while the contract is enabled";
          description = ''
            The claims sent to the inbox, as `<node>.<service>.<id>` of
            `{ ref; claim; copy; }`: the sent claim's reference, its entry in
            its node's claim set, and the copy the service holds of it, or
            null. Empty while the contract is disabled or `contracts.node` is
            null.
          '';
        };
        refs = lib.mkOption {
          type = lib.types.listOf lib.types.raw;
          readOnly = true;
          default = lib.sort (first: second: references.labelOf first < references.labelOf second) (
            map (entry: entry.ref) (entriesOf inbox.received)
          );
          defaultText = lib.literalMD "the references of `received`, sorted by label";
          description = ''
            The references of `received`, sorted by their label
            `<node>:<kind>.<service>.<id>`, so it is empty whenever
            `received` is.
          '';
        };
      };
    };
}
