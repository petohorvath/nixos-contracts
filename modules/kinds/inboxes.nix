# PROTOTYPE (claim-inboxes): the arguments of `mkClaimKind` for inboxes, a
# service's hold on a place where claims of any node arrive by their `to`.
{ lib }:
let
  # Kinds whose received claims the receiving service can hold a copy of.
  copyKinds = [ "secrets" ];

  # Nests a list of sends as `<node>.<service>.<id>`.
  nest =
    f: sends:
    lib.mapAttrs (
      _: byNode:
      lib.mapAttrs (
        _: byService:
        lib.mapAttrs (_: group: f (builtins.head group)) (lib.groupBy (send: send.ref.id) byService)
      ) (lib.groupBy (send: send.ref.service) byNode)
    ) (lib.groupBy (send: send.ref.node) sends);
in
{
  name = "inboxes";
  description = ''
    Inboxes of the service, by id: where claims that name the inbox in
    their `to` arrive, from any node.
  '';

  check =
    { claim, config, ... }:
    if claim.kind == "inboxes" || !(config.contracts.claimSets ? ${claim.kind}) then
      "it takes `${claim.kind}`, which is no claim kind an inbox takes on this node"
    else if claim.copy != null && !builtins.elem claim.kind copyKinds then
      "it copies what it receives, but `${claim.kind}` claims have no copies; set `copy = null` and read `received`"
    else
      null;

  claim =
    { service, config, ... }:
    let
      topConfig = config;
    in
    { name, config, ... }:
    let
      inbox = config;
      me = topConfig.contracts.node;
      nodeConfigs = lib.mapAttrs (_: node: node.config) topConfig.contracts.nodes // {
        ${me} = topConfig;
      };
      # What every node, this one included, sends to this inbox.
      sends =
        lib.filter (send: send.to.service == service && send.to.id == name && send.ref.kind == inbox.kind)
          (
            lib.concatMap (nodeConfig: (nodeConfig.contracts.sent or { }).${me} or [ ]) (
              lib.attrValues nodeConfigs
            )
          );
      # While the node collects what it sends, it has received nothing.
      received = lib.optionalAttrs (me != null && !topConfig.contracts.internal.collecting) (
        nest (send: {
          inherit (send) ref;
          # The sender's claim, as its node's claim set holds it.
          claim = (import ../references.nix).lookup topConfig send.ref;
          copy =
            if inbox.copy == null then
              null
            else
              topConfig.contracts.services.${service}.copies.${name}.${send.ref.node}.${send.ref.service}.${send.ref.id};
        }) sends
      );
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
            Null to only collect references, or definitions of the copy
            this service holds per received claim, such as its `group`.
            Each copy is a claim of the inbox's kind whose value copies the
            received reference.
          '';
        };
        received = lib.mkOption {
          type = lib.types.raw;
          readOnly = true;
          default = lib.mapAttrs (
            _: lib.mapAttrs (_: lib.mapAttrs (_: entry: entry // { claim = entry.claim.claim; }))
          ) received;
          description = ''
            Each claim sent here, as `<node>.<service>.<id>` of
            `{ ref; claim; copy; }`.
          '';
        };
        refs = lib.mkOption {
          type = lib.types.raw;
          readOnly = true;
          default = map (send: send.ref) (
            lib.sort (
              a: b: (import ../references.nix).labelOf a.ref < (import ../references.nix).labelOf b.ref
            ) sends
          );
          description = "The references of the received claims, ordered by reference.";
        };
      };
    };
}
