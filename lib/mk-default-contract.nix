{ lib }:
let
  wrap =
    value:
    if value ? _type then
      value
    else if lib.isAttrs value && value != { } && !(lib.isDerivation value) then
      lib.mapAttrs (_: wrap) value
    else
      lib.mkDefault value;
in
/**
  Mark every value of a contract definition as a default, so a host can
  override any single field at normal priority while the rest of the
  definition stays in place.

  Recurses through attribute sets and wraps each leaf in `lib.mkDefault`.
  Lists, empty attribute sets and derivations count as leaves, so a host that
  sets a list replaces it. A value that already carries a module property,
  such as `lib.mkForce`, is kept as written.

  # Inputs

  `contract`
  : A definition for one `contracts.services.<name>` entry.

  # Output

  The same definition with every leaf at default priority.

  # Example

  ```nix
  contracts.services.chrony = contractsLib.mkDefaultContract {
    identity.static.user = "chrony";
    binds.ntp = { proto = "udp"; port = 123; };
  };
  ```
*/
wrap
