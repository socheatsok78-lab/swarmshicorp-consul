#!/bin/sh
set -e

entrypoint_log() {
    if [ -z "${VAULT_ENTRYPOINT_QUIET_LOGS:-}" ]; then
        echo "$@"
    fi
}

DOCKER_BOOTSTRAP_ARGS=""
docker_bootstrap_set_arg() {
    if [[ -n "${DOCKER_BOOTSTRAP_ARGS}" ]]; then
        DOCKER_BOOTSTRAP_ARGS="${DOCKER_BOOTSTRAP_ARGS} "
    fi
    DOCKER_BOOTSTRAP_ARGS="${DOCKER_BOOTSTRAP_ARGS}${1}"
}

# Address Bind Options
#
# The address to which Consul will bind client interfaces, including the HTTP and DNS servers.
if [[ -z "${CONSUL_BIND}" ]] && [[ -z "$CONSUL_BIND_INTERFACE" ]]; then
    if [[ -n "${CONSUL_BIND_ADDRESS}" ]]; then
        CONSUL_BIND="-bind=$CONSUL_BIND_ADDRESS"
        echo "==> The CONSUL_BIND_INTERFACE is not set, using address '$CONSUL_BIND_ADDRESS' for bind option..."
    fi
fi
# The address to which Consul will bind client interfaces, including the HTTP and DNS servers.
if [[ -z "${CONSUL_CLIENT}" ]] && [[ -z "$CONSUL_CLIENT_INTERFACE" ]]; then
    if [[ -n "${CONSUL_CLIENT_ADDRESS}" ]]; then
        CONSUL_CLIENT="-client=$CONSUL_CLIENT_ADDRESS"
        echo "==> The CONSUL_CLIENT_INTERFACE is not set, using address '$CONSUL_CLIENT_ADDRESS' for client option..."
    fi
fi

# Advertise Address Options
# 
# # The advertise address is used to change the address that we advertise to other nodes in the cluster.
# By default, the -bind address is advertised.
if [[ -z "$CONSUL_ADVERTISE" ]]; then
    if [[ -n "$CONSUL_ADVERTISE_INTERFACE" ]]; then
        CONSUL_ADVERTISE_ADDRESS=$(ip -o -4 addr list $CONSUL_ADVERTISE_INTERFACE | head -n1 | awk '{print $4}' | cut -d/ -f1)
        if [ -z "$CONSUL_ADVERTISE_ADDRESS" ]; then
            echo "Could not find IP for interface '$CONSUL_ADVERTISE_INTERFACE', exiting"
            exit 1
        fi

        CONSUL_ADVERTISE="-advertise=$CONSUL_ADVERTISE_ADDRESS"
        echo "==> Found address '$CONSUL_ADVERTISE_ADDRESS' for interface '$CONSUL_ADVERTISE_INTERFACE', setting advertise option..."
    fi
fi
# The advertise WAN address is used to change the address that we advertise to server nodes joining through the WAN.
if [[ -z "$CONSUL_ADVERTISE_WAN" ]]; then
    if [[ -n "$CONSUL_ADVERTISE_WAN_INTERFACE" ]]; then
        CONSUL_ADVERTISE_WAN_ADDRESS=$(ip -o -4 addr list $CONSUL_ADVERTISE_WAN_INTERFACE | head -n1 | awk '{print $4}' | cut -d/ -f1)
        if [ -z "$CONSUL_ADVERTISE_WAN_ADDRESS" ]; then
            echo "Could not find IP for interface '$CONSUL_ADVERTISE_WAN_INTERFACE', exiting"
            exit 1
        fi

        CONSUL_ADVERTISE_WAN="-advertise-wan=$CONSUL_ADVERTISE_WAN_ADDRESS"
        echo "==> Found address '$CONSUL_ADVERTISE_WAN_ADDRESS' for interface '$CONSUL_ADVERTISE_WAN_INTERFACE', setting advertise-wan option..."
    fi
fi

# Datacenter Options
# 
# This flag controls the datacenter in which the agent is running.
# If not provided, it defaults to "dc1". Consul has first-class support for multiple datacenters,
# but it relies on proper configuration.
# 
# Nodes in the same datacenter should be on a single LAN.
if [[ -n "${CONSUL_DATACENTER}" ]]; then
    docker_bootstrap_set_arg "-datacenter=${CONSUL_DATACENTER}"
fi

# DNS and Domain Options
# 
# The DNS port to listen on. This overrides the default port 8600.
if [[ -n "${CONSUL_DNS_PORT}" ]]; then
    docker_bootstrap_set_arg "-dns-port=${CONSUL_DNS_PORT}"
fi
# By default, Consul responds to DNS queries in the "consul." domain.
# This flag can be used to change that domain.
# All queries in this domain are assumed to be handled by Consul and will not be recursively resolved.
if [[ -n "${CONSUL_DNS_DOMAIN}" ]]; then
    docker_bootstrap_set_arg "-domain=${CONSUL_DNS_DOMAIN}"
fi
# This flag allows Consul to respond to DNS queries in an alternate domain,
# in addition to the primary domain. If unset, no alternate domain is used.
if [[ -n "$CONSUL_DNS_ALT_DOMAIN" ]]; then
    docker_bootstrap_set_arg "-alt-domain=${CONSUL_DNS_ALT_DOMAIN}"
fi

# Node Options
# 
# The name of this node in the cluster. This must be unique within the cluster.
# By default this is the hostname of the machine.
# The node name cannot contain whitespace or quotation marks.
# To query the node from DNS, the name must only contain alphanumeric characters and hyphens (-).
if [[ -z "${CONSUL_NODE_NAME}" ]]; then
    CONSUL_NODE_NAME=$(hostname -s)
fi
docker_bootstrap_set_arg "-node=${CONSUL_NODE_NAME}"

# Log Options
# 
# The level of logging to show after the Consul agent has started.
# This defaults to "info". The available log levels are "trace", "debug", "info", "warn", and "error".
CONSUL_LOG_LEVEL=${CONSUL_LOG_LEVEL:-"INFO"}
docker_bootstrap_set_arg "-log-level=${CONSUL_LOG_LEVEL}"

# This flag enables the agent to output logs in a JSON format.
CONSUL_LOG_JSON=${CONSUL_LOG_JSON:-"false"}
docker_bootstrap_set_arg "-log-json=${CONSUL_LOG_JSON}"

# run the original entrypoint
if [ "$1" = 'agent' ]; then
    set -- "$@" $CONSUL_BIND $CONSUL_CLIENT $CONSUL_ADVERTISE $CONSUL_ADVERTISE_WAN $DOCKER_BOOTSTRAP_ARGS
fi
exec docker-entrypoint.sh "${@}"
