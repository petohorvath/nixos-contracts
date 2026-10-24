# How a reference reads its node, shared by the secrets kind, which resolves
# and checks references, and backend adapters, which read the resolved ones.
{
  # The configuration a reference reads, or null for a node missing from
  # the node collection.
  nodeConfigOrNull =
    config: reference:
    if reference.node == null then config else config.contracts.nodes.${reference.node}.config or null;

  # A reference as messages name it: its claim name, after its node's name
  # when another node holds it.
  labelOf =
    reference: if reference.node == null then reference.name else "${reference.node}:${reference.name}";
}
