/*
  PROTOTYPE (claim-inboxes): install every authored secret claim and every
  received copy with agenix-rekey. The adapter names its own entries from a
  claim's address, `<service>-<id>` for an authored claim and
  `<service>-<inbox>-<node>-<sender>-<id>` for a copy, and checks that no
  two addresses make one name.
*/
{ config, lib, ... }:
let
  inherit (import ../../modules/references.nix) labelOf addressLabel nodeConfigOrNull;

  nameOf = address: lib.concatStringsSep "-" address;

  authored = lib.concatMap lib.attrValues (lib.attrValues config.contracts.claimSets.secrets);
  secrets = authored ++ config.contracts.copies;

  isCopy = secret: secret.value ? copy;

  # The backend entry a source names, or null when the core rejected the
  # reference or its node has no entry for it. A source is always an
  # authored claim, so its entry's name follows from its address alone.
  entryOrNull =
    source:
    if source.claim == null then
      null
    else
      (nodeConfigOrNull config source).age.secrets.${nameOf source.claim.address} or null;

  copiedEntryOrNull = secret: entryOrNull (lib.head secret.sources);

  generatorOf =
    value:
    if value ? generate then
      value.generate
    else if value ? derive then
      value.derive.generator
    else
      null;

  backendAssertion = secret: source: {
    assertion = source.claim == null || entryOrNull source != null;
    message = "secret `${addressLabel secret.address}` references `${labelOf source}`, whose node has no `nixosModules.agenix-rekey`.";
  };

  nameAssertions = lib.mapAttrsToList (name: group: {
    assertion = builtins.length group == 1;
    message = "secrets ${
      lib.concatMapStringsSep " and " (secret: "`${addressLabel secret.address}`") group
    } share the agenix name `${name}`; give one of them another id.";
  }) (lib.groupBy (secret: nameOf secret.address) secrets);
in
{
  config = {
    age.secrets = lib.listToAttrs (
      map (
        secret:
        let
          generator = generatorOf secret.value;
        in
        lib.nameValuePair (nameOf secret.address) {
          inherit (secret) group mode owner;
          generator = lib.mkIf (generator != null) {
            script = lib.mkDefault generator;
            dependencies = lib.mkIf (secret.value ? derive) (
              lib.filter (entry: entry != null) (map entryOrNull secret.sources)
            );
          };
          rekeyFile = lib.mkIf (isCopy secret) (lib.mkDefault (copiedEntryOrNull secret).rekeyFile or null);
        }
      ) secrets
    );

    contracts = {
      kinds.secrets.backend = {
        generators = lib.attrNames config.age.generators;
        location =
          address: config.age.secrets.${nameOf address}.path or "${config.age.secretsDir}/${nameOf address}";
      };

      assertions =
        nameAssertions
        ++ map (secret: {
          assertion = config.age.secrets.${nameOf secret.address}.rekeyFile != null;
          message =
            if isCopy secret then
              "secret `${addressLabel secret.address}` copies `${labelOf secret.value.copy}`, which has no encrypted file."
            else
              "secret `${addressLabel secret.address}` has no encrypted file.";
        }) (lib.filter (secret: !(isCopy secret) || copiedEntryOrNull secret != null) secrets)
        ++ lib.concatMap (secret: map (backendAssertion secret) secret.sources) secrets;
    };
  };
}
