# The arguments of `mkClaimKind` for inboxes: where claims of one kind
# arrive from any node, the node itself included, by their `sendTo`.
{ lib }:
let
  references = import ../references.nix;

  # Nests sends by the sent claim, as `<node>.<service>.<id>` of what `f`
  # makes of each, keeping one of the sends of a claim that names the
  # inbox twice.
  mapBySentClaim =
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
in
{
  name = "inboxes";
  description = ''
    Inboxes of the service, by id: where claims of one kind arrive from
    any node, the node itself included, when they name the inbox in their
    `sendTo`.
  '';

  # An inbox is where claims arrive, so it is sent nowhere.
  sendable = false;

  check =
    { claim, config, ... }:
    if !(config.contracts.claimSets ? ${claim.kind}) then
      "it takes `${claim.kind}`, which is no claim kind of this node"
    else if !config.contracts.internal.kinds.${claim.kind}.sendable then
      "it takes `${claim.kind}`, which no claim can be sent as"
    else if claim.copy != null && claim.kind != "secrets" then
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
      # send names, and its contract is enabled.
      receives = node != null && topConfig.contracts.services.${service}.enable;

      sends = lib.filter (
        send: send.to.service == service && send.to.id == name && send.ref.kind == inbox.kind
      ) sendsHere;

      # An inbox whose kind has no copies holds none, though it sets `copy`,
      # which its check reports.
      holdsCopies = inbox.copy != null && inbox.kind == "secrets";

      # A copy is a secret claim of this service, so its owner and group
      # follow this service's identity, placed by its own location.
      copyType = lib.types.submoduleWith {
        modules = [
          (topConfig.contracts.internal.kinds.secrets.claim service)
          {
            options.location = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              readOnly = true;
              description = ''
                The names that place the copy within its node,
                `[ <service> <inbox> <node> <sender service> <id> ]`.
              '';
            };
          }
        ];
      };

      # The settings of each copy, merged into one module and checked
      # against the copy's type at once, so a misspelt setting fails at
      # `copy` whether or not anything was received. The check reads only
      # this service's own options, so it adds no dependence on other nodes.
      # The module system substitutes the submodules of an option it
      # declares, so the substituted type keeps the check.
      copySettingsTypeOf =
        deferred:
        deferred
        // {
          merge =
            loc: defs:
            let
              settings = deferred.merge loc defs;
            in
            if inbox.kind == "secrets" then builtins.seq (copyType.merge loc defs) settings else settings;
          substSubModules = modules: copySettingsTypeOf (deferred.substSubModules modules);
        };
    in
    {
      options = {
        kind = lib.mkOption {
          type = lib.types.str;
          default = "secrets";
          description = "The claim kind the inbox takes.";
        };
        copy = lib.mkOption {
          type = lib.types.nullOr (copySettingsTypeOf lib.types.deferredModule);
          default = null;
          description = ''
            Null to only receive references, or the settings of the copy the
            service holds of each secret it receives, such as its `mode`.
            Only an inbox of secrets holds copies.
          '';
        };
        received = lib.mkOption {
          # Lazy, so reading one received claim forces no other. `attrsOf`
          # would force only each entry's attribute set, which reads no
          # node, so it would not recurse either and no test tells them
          # apart.
          type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw));
          readOnly = true;
          default = lib.optionalAttrs receives (
            mapBySentClaim (send: {
              inherit (send) ref;
              # The sent claim as its node's claim set holds it.
              inherit ((topConfig.contracts.lookup send.ref)) claim;
              copy =
                if holdsCopies then inbox.copies.${send.ref.node}.${send.ref.service}.${send.ref.id} else null;
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
            map (entry: entry.ref) (references.receivedOf inbox)
          );
          defaultText = lib.literalMD "the references of `received`, sorted by label";
          description = ''
            The references of `received`, sorted by their label
            `<node>:<kind>.<service>.<id>`, so it is empty whenever
            `received` is.
          '';
        };
        # Held here rather than in a claim set, whose keys must never
        # depend on other nodes. Lazy, as `received` is, so reading one
        # copy merges no other; `attrsOf` would force only each copy's
        # settings module, so it would not recurse either.
        copies = lib.mkOption {
          type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf (lib.types.lazyAttrsOf copyType));
          internal = true;
          readOnly = true;
          default = lib.optionalAttrs (receives && holdsCopies) (
            mapBySentClaim (send: {
              imports = [ inbox.copy ];
              location = [
                service
                name
                send.ref.node
                send.ref.service
                send.ref.id
              ];
              value.copied = send.ref;
            }) sends
          );
          defaultText = lib.literalMD "a copy of each secret sent here, while `copy` is set";
          description = ''
            The copies the service holds of the secrets sent to the inbox,
            as `<node>.<service>.<id>`, read through `received`.
          '';
        };
      };
    };
}
