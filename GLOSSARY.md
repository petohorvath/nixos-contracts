# Service contracts

A service contract describes what a service on one NixOS configuration runs as, offers and needs, so other modules can derive their configuration from it.

## Language

**Contract**:
A typed, writable description of one service's identity and claims within one configuration. It names no fleet concept, such as a network, except the node of a reference, and holds none of the service's own settings.
_Avoid_: Manifest, interface, surface

**Service**:
Something that runs on the configuration and that a contract describes. A helper daemon with its own process, such as a metrics exporter, is a service of its own.
_Avoid_: Integration, unit, workload

**Identity**:
What a service effectively runs as: a static account, or a dynamic identity that systemd allocates for one named unit. Who owns the service's files follows from it.

**Claim**:
A service's declared hold on one unit of something the configuration provides or needs: a bind, a mount or a secret. Two services cannot hold the same claim.
_Avoid_: Resource, requirement, building block

**Claim kind**:
One kind of claim, such as binds, mounts or secrets. The set of kinds is open: a new kind is defined the same way as the shipped ones.

**Claim name**:
The name a claim goes by within one configuration and on its backend, made of its service's name and the id the claim has within its contract, such as `influxdb-data`. Two claims of one kind with the same claim name clash; a reference does not name a claim by it.
_Avoid_: Key, full name

**Claim set**:
The read-only, configuration-wide collection of one kind's claims from enabled contracts, each as its contract holds it, keyed by claim name.

**Bind**:
Where a service accepts traffic: a protocol, a port and the addresses it listens on. It says where the service listens, never who may reach it.
_Avoid_: Listener, endpoint

**Mount**:
A path whose contents must survive, under one class. It says what must survive, never how a backend keeps it.
_Avoid_: Persisted path, bind mount, share

**Class**:
The name of a root of persistent storage a mount belongs to, such as state or cache. Where a class physically lives is up to an adapter.
_Avoid_: Category, tier

**Secret**:
A runtime credential a service needs. It says what the service reads, who may read it, which generator makes its value when the service makes its own, and which secrets its value comes from, never how a backend stores, shares or installs it.
_Avoid_: Credential, age secret, key

**Reference**:
A pointer to one claim by its node, kind, service and id. It always names its node, so it means the same claim on every node that reads it. A secret references the secrets its value comes from: without a generator it is a copy of the one secret it references, and a generator makes its value from the secrets it references.
_Avoid_: Handle, link, dependency, source

**Node**:
One NixOS configuration among those evaluated together, whether it describes a host, a guest or an external device. A node writes its own contracts and overrides the service modules' defaults; a reference names a node by its node identity.
_Avoid_: Host, machine, peer

**Node collection**:
The nodes a reference may name, each by its node identity, as one configuration is given them.
_Avoid_: Nodes list, peers

**Node identity**:
A node's name within its node collection, independent of its hostname.
_Avoid_: Hostname, node name

**Generator**:
A named way to make a secret's value, such as `alnum`, for a value the service makes on its own rather than one a person or another party provides. A backend adapter provides the generators a secret may name.
_Avoid_: Generator script, provenance, source

**Delivery**:
Handing a secret to a dynamic identity's unit, so its daemon reads it from where the unit receives it rather than where the backend installs it. A delivery adapter provides it.
_Avoid_: Injection, mounting

**Adapter**:
An opt-in module that turns one claim kind's claim set into one backend's configuration, such as preservation or agenix-rekey.
_Avoid_: Materialiser, consumer

**Adapter slot**:
The place where one adapter gives a claim kind the data it needs, such as the secret backend's location and generators. Only one adapter fills a slot, and a node writes none.
_Avoid_: Rule, hook, setting

**Check**:
A condition over the configuration's contracts that must hold, such as two claims not clashing. A failed check reports its message.
_Avoid_: Assertion, validation
