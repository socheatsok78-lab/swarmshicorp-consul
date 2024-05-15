# About

A wrapper for HashiCorp Consul to aid deployment inside Docker Swarm.

## Docker networking

The deployment spec defined the following network interfaces:

- `public_network`: The interface that allow external communication to the Consul agent. By default the `public_network` is bound to the `eth0` interface.
- `server_network`: The interface that allow communication between Consul servers. By default the `server_network` is bound to the `eth1` interface.
- `host_network`: The interface that allow communication between the Consul agent and the host. By default the `host_network` is bound to the `eth3` interface.

> [!NOTE]
> The `eth2` interface is reserved for `ingress` traffic. This is the default interface for Docker Swarm ingress network.
