#!/bin/bash
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
        entrypoint_log "==> The CONSUL_BIND_INTERFACE is not set, using address '$CONSUL_BIND_ADDRESS' for bind option..."
    fi
fi
# The address to which Consul will bind client interfaces, including the HTTP and DNS servers.
if [[ -z "${CONSUL_CLIENT}" ]] && [[ -z "$CONSUL_CLIENT_INTERFACE" ]]; then
    if [[ -n "${CONSUL_CLIENT_ADDRESS}" ]]; then
        CONSUL_CLIENT="-client=$CONSUL_CLIENT_ADDRESS"
        entrypoint_log "==> The CONSUL_CLIENT_INTERFACE is not set, using address '$CONSUL_CLIENT_ADDRESS' for client option..."
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
        entrypoint_log "==> Found address '$CONSUL_ADVERTISE_ADDRESS' for interface '$CONSUL_ADVERTISE_INTERFACE', setting advertise option..."
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
        entrypoint_log "==> Found address '$CONSUL_ADVERTISE_WAN_ADDRESS' for interface '$CONSUL_ADVERTISE_WAN_INTERFACE', setting advertise-wan option..."
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

# Bootstrap Options
# 
# This flag provides the number of expected servers in the datacenter.
# Either this value should not be provided or the value must agree with other servers in the cluster.
# When provided, Consul waits until the specified number of servers are available and then bootstraps the cluster.
# This allows an initial leader to be elected automatically. 
if [[ -n "$CONSUL_BOOTSTRAP_EXPECT" ]]; then
    docker_bootstrap_set_arg "-bootstrap-expect=${CONSUL_BOOTSTRAP_EXPECT}"
fi
# Address of another agent to join upon starting up. Joining is retried until success. Once the agent joins successfully as a member,
# it will not attempt to join again. After joining, the agent solely maintains its membership via gossip.
# This option can be specified multiple times to specify multiple agents to join. By default, the agent won't join any nodes when it starts up.
# The value can contain IPv4, IPv6, or DNS addresses. Literal IPv6 addresses must be enclosed in square brackets.
# If multiple values are given, they are tried and retried in the order listed until the first succeeds.
if [[ -n "${CONSUL_RETRY_JOIN_TEMPLATE}" ]]; then
    CONSUL_RETRY_JOIN_ARG="$(eval echo -retry-join=${CONSUL_RETRY_JOIN_TEMPLATE})"
    CONSUL_RETRY_JOIN_ARG="$(eval echo ${CONSUL_RETRY_JOIN_ARG})"
    docker_bootstrap_set_arg "${CONSUL_RETRY_JOIN_ARG}"
elif [[ -n "$CONSUL_RETRY_JOIN" ]]; then
    docker_bootstrap_set_arg "-retry-join=${CONSUL_RETRY_JOIN}"
fi

# Time to wait between join attempts. Defaults to 30s.
if [[ -n "$CONSUL_RETRY_INTERVAL" ]]; then
    docker_bootstrap_set_arg "-retry-interval=${CONSUL_RETRY_INTERVAL}"
fi
# The maximum number of join attempts if using -retry-join before exiting with return code 1.
# By default, this is set to 0 which is interpreted as infinite retries.
if [[ -n "$CONSUL_RETRY_MAX" ]]; then
    docker_bootstrap_set_arg "-retry-max=${CONSUL_RETRY_MAX}"
fi

# ddress of another WAN agent to join upon starting up. WAN joining is retried until success.
# This can be specified multiple times to specify multiple WAN agents to join. If multiple values are given,
# they are tried and retried in the order listed until the first succeeds.
# By default, the agent won't WAN join any nodes when it starts up.
if [[ -n "${CONSUL_RETRY_JOIN_WAN_TEMPLATE}" ]]; then
    CONSUL_RETRY_JOIN_WAN_ARG=$(eval echo -retry-join=${CONSUL_RETRY_JOIN_WAN_TEMPLATE})
    CONSUL_RETRY_JOIN_WAN_ARG="$(eval echo ${CONSUL_RETRY_JOIN_WAN_ARG})"
    docker_bootstrap_set_arg "${CONSUL_RETRY_JOIN_WAN_ARG}"
elif [[ -n "$CONSUL_RETRY_JOIN_WAN" ]]; then
    docker_bootstrap_set_arg "-retry-join-wan=${CONSUL_RETRY_JOIN_WAN}"
fi
# Time to wait between -retry-join-wan attempts. Defaults to 30s.
if [[ -n "$CONSUL_RETRY_INTERVAL_WAN" ]]; then
    docker_bootstrap_set_arg "-retry-interval-wan=${CONSUL_RETRY_INTERVAL_WAN}"
fi
# The maximum number of -retry-join-wan attempts to be made before exiting with return code 1.
# By default, this is set to 0 which is interpreted as infinite retries.
if [[ -n "$CONSUL_RETRY_MAX_WAN" ]]; then
    docker_bootstrap_set_arg "-retry-max-wan=${CONSUL_RETRY_MAX_WAN}"
fi

# Similar to -retry-join-wan but allows retrying discovery of fallback addresses for
# the mesh gateways in the primary datacenter if the first attempt fails.
# This is useful for cases where we know the address will become available eventually.
if [[ -n "$CONSUL_PRIMARY_GATEWAY" ]]; then
    docker_bootstrap_set_arg "-primary-gateway=${CONSUL_PRIMARY_GATEWAY}"
fi
# When provided, Consul will ignore a previous leave and attempt to rejoin the cluster when starting.
# By default, Consul treats leave as a permanent intent and does not attempt to join the cluster again when starting.
# This flag allows the previous state to be used to rejoin the cluster.
if [[ -n "$CONSUL_REJOIN" ]]; then
    docker_bootstrap_set_arg "-rejoin"
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
    shift
    set -- agent $CONSUL_BIND $CONSUL_CLIENT $CONSUL_ADVERTISE $CONSUL_ADVERTISE_WAN $DOCKER_BOOTSTRAP_ARGS "$@"
fi
exec docker-entrypoint.sh "${@}"
