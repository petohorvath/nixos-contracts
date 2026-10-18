---
status: accepted
---

# Keep the `contracts` option root

The library declares its options under the top-level `contracts.*` root, matching the repository name, even though nixpkgs draft PR [#506343](https://github.com/NixOS/nixpkgs/pull/506343), an implementation of [RFC 189](https://github.com/NixOS/rfcs/pull/189), would declare the same root and `lib.contracts`. If that PR merges, every NixOS evaluation that imports this library fails with a duplicate option declaration. We accept the risk because the PR is an unmerged draft with an uncertain future, the library has a single consumer today, and renaming the root then is a mechanical change.

## Considered Options

A distinct root such as `serviceContracts.*` avoids the collision for good, at the cost of a root that no longer matches the repository name. The two designs also differ in purpose: RFC 189 routes one requirement to a swappable provider, while a contract here describes one service's identity and claims. They may meet later, with an adapter handing secret claims to an RFC 189 provider.

## Consequences

Watch #506343 and its successors. If nixpkgs claims `contracts`, rename the root before adopting that nixpkgs revision, and record the rename in the changelog for any consumer that has adopted the library by then.
