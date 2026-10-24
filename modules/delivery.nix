# PROTOTYPE (claim-inboxes): delivers each claim's reference to the inboxes
# its `to` names, and holds the copies a service keeps of what it received.
#
# A node's sends are read from its claim sets, which hold authored claims
# only; received copies sit in `contracts.services.<s>.copies`, outside
# them, so what a node sends never depends on what any node receives.
# `contracts.checks.routing` reads the sends from a second evaluation in
# which no inbox has received anything instead, which turns a send that
# depends on what was received into a named check, at the cost of
# evaluating every node twice.
{
  config,
  lib,
  extendModules,
  ...
}:
let
  references = import ./references.nix;
  inherit (references) labelOf addressLabel;
  cfg = config.contracts;

  flatten = claimSet: lib.concatMap lib.attrValues (lib.attrValues claimSet);

  sendsOf =
    contracts:
    lib.concatMap (
      kind:
      lib.concatMap (
        claim:
        map (to: {
          inherit (claim) ref address;
          inherit to;
        }) claim.to
      ) (flatten contracts.claimSets.${kind})
    ) (lib.filter (kind: kind != "inboxes") (lib.attrNames contracts.claimSets));

  # This node as if no inbox had received anything.
  collected =
    (extendModules { modules = [ { contracts.internal.collecting = true; } ]; }).config.contracts;

  senderAssertion =
    send:
    let
      result = cfg.lookup send.to;
      prefix = "${send.ref.kind} claim `${addressLabel send.address}` sends to `${labelOf send.to}`";
    in
    if result.reason != null then
      {
        assertion = false;
        message = "${prefix}: ${result.reason}.";
      }
    else
      {
        assertion = result.claim.kind == send.ref.kind;
        message = "${prefix}, which takes `${result.claim.kind}`, not `${send.ref.kind}`.";
      };

  driftAssertion =
    let
      label = send: "${addressLabel send.address} -> ${labelOf send.to}";
      lost = lib.subtractLists (map label (sendsOf collected)) (map label (sendsOf cfg));
    in
    {
      assertion = lost == [ ];
      message = "sends ${
        lib.concatMapStringsSep ", " (send: "`${send}`") lost
      } exist only once this node has received claims, so they are never delivered: neither a claim that sends nor its `to` may depend on an inbox's `received`.";
    };
in
{
  options.contracts = {
    checks.routing = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to read each node's sends from a second evaluation of the
        node, so a send that depends on what the node received fails a
        named check instead of recursing. Doubles the evaluation of every
        node; meant for CI.
      '';
    };
    internal.collecting = lib.mkOption {
      type = lib.types.bool;
      internal = true;
      default = false;
      description = "Whether this is the evaluation that collects what the node sends.";
    };
    sent = lib.mkOption {
      type = lib.types.raw;
      internal = true;
      readOnly = true;
      default = lib.groupBy (send: send.to.node) (
        lib.filter (send: send.to.node != null) (
          sendsOf (if cfg.checks.routing && !cfg.internal.collecting then collected else cfg)
        )
      );
      description = "What this node sends, by receiving node.";
    };
    services = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, config, ... }:
          let
            service = name;
            claimModule = cfg.internal.claimModules.secrets { inherit service; };
            copyType = lib.types.submoduleWith {
              modules = [
                claimModule
                {
                  options = {
                    service = lib.mkOption { type = lib.types.str; };
                    address = lib.mkOption { type = lib.types.listOf lib.types.str; };
                  };
                }
              ];
            };
            inherit (lib.types) lazyAttrsOf;
          in
          {
            options.copies = lib.mkOption {
              type = lazyAttrsOf (lazyAttrsOf (lazyAttrsOf (lazyAttrsOf copyType)));
              default = { };
              description = ''
                The copies the service holds of claims it received, as
                `<inbox>.<node>.<service>.<id>`. They sit outside the claim
                sets, so no node reads them to find what it sends.
              '';
            };
            config.copies = lib.mapAttrs (
              inboxId: inbox:
              lib.mapAttrs (
                node:
                lib.mapAttrs (
                  sender:
                  lib.mapAttrs (
                    id: entry:
                    let
                      address = [
                        service
                        inboxId
                        node
                        sender
                        id
                      ];
                    in
                    {
                      imports = [ inbox.copy ];
                      inherit service address;
                      _module.args = { inherit address; };
                      value.copy = entry.ref;
                    }
                  )
                )
              ) (if inbox.copy == null || !config.enable then { } else inbox.received)
            ) config.inboxes;
          }
        )
      );
    };

    # Every received copy of an enabled contract, for adapters.
    copies = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      default = lib.concatMap (
        contract:
        lib.concatMap (
          byNode:
          lib.concatMap (byService: lib.concatMap lib.attrValues (lib.attrValues byService)) (
            lib.attrValues byNode
          )
        ) (lib.attrValues contract.copies)
      ) (lib.attrValues (lib.filterAttrs (_: contract: contract.enable) cfg.services));
      description = "Every received copy of an enabled contract, as a list.";
    };
  };

  config.contracts.assertions = lib.optionals (!cfg.internal.collecting) (
    map senderAssertion (sendsOf cfg)
    ++ lib.optional cfg.checks.routing driftAssertion
    # Received copies pass the secrets kind's check like authored claims.
    ++ lib.concatMap (
      copy:
      map
        (reason: {
          assertion = false;
          message = "secrets copy `${addressLabel copy.address}`: ${reason}.";
        })
        (
          cfg.internal.claimChecks.secrets {
            inherit (copy) service;
            claim = copy;
          }
        )
    ) cfg.copies
  );
}
