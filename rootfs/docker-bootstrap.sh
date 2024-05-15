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

DOCKER_BOOTSTRAP_NODE_META=""
docker_bootstrap_set_node_meta() {
    if [[ -n "${1}" ]] && [[ -n "${2}" ]]; then
        if [[ -n "${DOCKER_BOOTSTRAP_NODE_META}" ]]; then
            DOCKER_BOOTSTRAP_NODE_META="${DOCKER_BOOTSTRAP_NODE_META} "
        fi
        entrypoint_log "==> Assigning node meta '${1}=${2}'"
        DOCKER_BOOTSTRAP_NODE_META="${DOCKER_BOOTSTRAP_NODE_META}-node-meta ${1}:${2}"
    fi
}

# CONSUL_DATA_DIR is exposed as a volume for possible persistent storage. The
# CONSUL_CONFIG_DIR isn't exposed as a volume but you can compose additional
# config files in there if you use this image as a base, or use CONSUL_LOCAL_CONFIG
# below.
if [ -z "$CONSUL_DATA_DIR" ]; then
  CONSUL_DATA_DIR=/consul/data
fi

if [ -z "$CONSUL_CONFIG_DIR" ]; then
  CONSUL_CONFIG_DIR=/consul/config
fi

if [[ -n "${HASHICORP_NODE_PROVISIONING}" ]]; then
    HASHICORP_NODE_PROVISIONING_DIR=${HASHICORP_NODE_PROVISIONING_DIR:-"/.swarmshicorp-node-provisioning"}
    HASHICORP_NODE_PROVISIONING_FILE=${HASHICORP_NODE_PROVISIONING_FILE:-"${HASHICORP_NODE_PROVISIONING_DIR}/activate"}

    while [ ! -f "$HASHICORP_NODE_PROVISIONING_FILE" ]; do
        entrypoint_log "==> Waiting for node provisioning file '$HASHICORP_NODE_PROVISIONING_FILE' to be created..."
        sleep 1
    done

    source "$HASHICORP_NODE_PROVISIONING_FILE"

    CONSUL_BIND_ADDRESS=$HASHICORP_NODE_BIND_ADDRESS
    CONSUL_CLIENT_ADDRESS=$HASHICORP_NODE_CLIENT_ADDRESS
    CONSUL_ADVERTISE_ADDRESS=$HASHICORP_NODE_ADVERTISE_ADDRESS
    CONSUL_ADVERTISE_WAN_ADDRESS=$HASHICORP_NODE_ADVERTISE_WAN_ADDRESS
fi

# Consul Autopilot for Docker Swarm
if [[ -n "${CONSUL_DOCKERSWARM_AUTOPILOT}" ]]; then
    entrypoint_log "==> Enable Consul Autopilot for Docker Swarm..."

    # Use DOCKERSWARM_SERVICE_NAME with DOCKERSWARM_TASK_SLOT as node name
    # To ensure that the node name is a valid domain name, we replace '_' with '-'
    CONSUL_NODE_NAME=$(echo "${DOCKERSWARM_SERVICE_NAME}_${DOCKERSWARM_TASK_SLOT}" | tr '_' '-')
    entrypoint_log "==> [Docker Swarm Autopilot] Using '$CONSUL_NODE_NAME' as node name..."

    CONSUL_DISABLE_HOST_NODE_ID=true
    if [ -f "$CONSUL_DATA_DIR/node-id" ]; then
        CONSUL_NODE_ID=$(cat "$CONSUL_DATA_DIR/node-id")
        entrypoint_log "==> [Docker Swarm Autopilot] Using '$CONSUL_NODE_ID' as node ID..."
    else
        entrypoint_log "==> [Docker Swarm Autopilot] Generate a random node ID which will be persisted in the data directory..."
    fi
fi

# Address Bind Options
#
# The address to which Consul will bind client interfaces, including the HTTP and DNS servers.
if [[ -z "${CONSUL_BIND}" ]] && [[ -z "$CONSUL_BIND_INTERFACE" ]]; then
    if [[ -z "${CONSUL_BIND_ADDRESS}" ]]; then
        CONSUL_BIND_ADDRESS=0.0.0.0
    fi
    if [[ -n "${CONSUL_BIND_ADDRESS}" ]]; then
        CONSUL_BIND="-bind=$CONSUL_BIND_ADDRESS"
        entrypoint_log "==> The CONSUL_BIND_INTERFACE is not set, using address '$CONSUL_BIND_ADDRESS' for bind option..."
    fi
fi
# The address to which Consul will bind client interfaces, including the HTTP and DNS servers.
if [[ -z "${CONSUL_CLIENT}" ]] && [[ -z "$CONSUL_CLIENT_INTERFACE" ]]; then
    if [[ -z "${CONSUL_CLIENT_ADDRESS}" ]]; then
        CONSUL_CLIENT_ADDRESS=0.0.0.0
    fi
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
# Generate a new UUID for the Consul agent using the short hostname.
# This is used to determine the node's identity in the gossip protocol.
if [[ -n "${CONSUL_DISABLE_HOST_NODE_ID}" ]]; then
    docker_bootstrap_set_arg "-disable-host-node-id"
elif [[ -z "${CONSUL_NODE_ID}" ]]; then
    CONSUL_NODE_ID=$(uuidgen --namespace @dns --name $(hostname -s) --sha1)
    docker_bootstrap_set_arg "-node-id=${CONSUL_NODE_ID}"
    entrypoint_log "==> Generated node ID '$CONSUL_NODE_ID' for node '$(hostname)'..."
elif [[ -n "${CONSUL_NODE_ID}" ]]; then
    docker_bootstrap_set_arg "-node-id=${CONSUL_NODE_ID}"
fi

# The name of this node in the cluster. This must be unique within the cluster.
# By default this is the hostname of the machine.
# The node name cannot contain whitespace or quotation marks.
# To query the node from DNS, the name must only contain alphanumeric characters and hyphens (-).
if [[ -z "${CONSUL_NODE_NAME}" ]]; then
    CONSUL_NODE_NAME=$(hostname -s)
fi
docker_bootstrap_set_arg "-node=${CONSUL_NODE_NAME}"
docker_bootstrap_set_node_meta "dockerswarm-consul-node-name" "$CONSUL_NODE_NAME"

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
if [[ -n "$CONSUL_RETRY_JOIN" ]]; then
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
if [[ -n "$CONSUL_RETRY_JOIN_WAN" ]]; then
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

# Docker Swarm specific metadata of the node and service
# Example:
# - DOCKERSWARM_SERVICE_ID={{.Service.ID}}
# - DOCKERSWARM_SERVICE_NAME={{.Service.Name}}
# - DOCKERSWARM_NODE_ID={{.Node.ID}}
# - DOCKERSWARM_NODE_HOSTNAME={{.Node.Hostname}}
# - DOCKERSWARM_TASK_ID={{.Task.ID}}
# - DOCKERSWARM_TASK_NAME={{.Task.Name}}
# - DOCKERSWARM_TASK_SLOT={{.Task.Slot}}
# - DOCKERSWARM_TASK_SLOT={{.Task.Slot}}
# - DOCKERSWARM_STACK_NAMESPACE={{ index .Service.Labels "com.docker.stack.namespace"}}
docker_bootstrap_set_node_meta "dockerswarm-service-id" "$DOCKERSWARM_SERVICE_ID"
docker_bootstrap_set_node_meta "dockerswarm-service-name" "$DOCKERSWARM_SERVICE_NAME"
docker_bootstrap_set_node_meta "dockerswarm-node-id" "$DOCKERSWARM_NODE_ID"
docker_bootstrap_set_node_meta "dockerswarm-node-hostname" "$DOCKERSWARM_NODE_HOSTNAME"
docker_bootstrap_set_node_meta "dockerswarm-task-id" "$DOCKERSWARM_TASK_ID"
docker_bootstrap_set_node_meta "dockerswarm-task-name" "$DOCKERSWARM_TASK_NAME"
docker_bootstrap_set_node_meta "dockerswarm-task-slot" "$DOCKERSWARM_TASK_SLOT"
docker_bootstrap_set_node_meta "dockerswarm-stack-namespace" "$DOCKERSWARM_STACK_NAMESPACE"

# Consul Configuration for Docker Swarm

CONSUL_REJOIN_AFTER_LEAVE=${CONSUL_REJOIN_AFTER_LEAVE:-"true"}
CONSUL_CHECK_UPDATE_INTERVAL=${CONSUL_CHECK_UPDATE_INTERVAL:-"5m"}
CONSUL_AUTOPILOT_CLEANUP_DEAD_SERVERS=${CONSUL_AUTOPILOT_CLEANUP_DEAD_SERVERS:-"true"}
CONSUL_AUTOPILOT_LAST_CONTACT_THRESHOLD=${CONSUL_AUTOPILOT_LAST_CONTACT_THRESHOLD:-"1m"}

entrypoint_log "==> Generating configuration file at \"$CONSUL_CONFIG_DIR/docker.hcl\"..."
cat <<EOT > "$CONSUL_CONFIG_DIR/docker.hcl"
# Consul will ignore a previous leave and attempt to rejoin the cluster when starting.
# By default, Consul treats leave as a permanent intent and does not attempt to join the cluster again when starting.
# This flag allows the previous state to be used to rejoin the cluster.
rejoin_after_leave = $CONSUL_REJOIN_AFTER_LEAVE

# leave_on_terminate = On agents in client-mode, this defaults to true and for agents in server-mode, this defaults to false.

# This interval controls how often check output from checks in a steady state is synchronized with the server.
# Many checks which are in a steady state produce slightly different output per run (timestamps, etc) which cause constant writes.
# This configuration allows deferring the sync of check output for a given interval to reduce write pressure.
# If a check ever changes state, the new state and associated output is synchronized immediately.
# By default, this is set to 5 minutes ("5m").
# To disable this behavior, set the value to "0s".
check_update_interval = "$CONSUL_CHECK_UPDATE_INTERVAL"

# Disables automatic checking for security bulletins and new version releases.
disable_update_check = true

autopilot {
    cleanup_dead_servers = $CONSUL_AUTOPILOT_CLEANUP_DEAD_SERVERS
    last_contact_threshold = "$CONSUL_AUTOPILOT_LAST_CONTACT_THRESHOLD"
}

telemetry {
    prometheus_retention_time = "24h"
    disable_hostname = true
}
EOT

# run the original entrypoint
if [ "$1" = 'agent' ]; then
    shift
    set -- agent $CONSUL_BIND $CONSUL_CLIENT $CONSUL_ADVERTISE $CONSUL_ADVERTISE_WAN $DOCKER_BOOTSTRAP_ARGS $DOCKER_BOOTSTRAP_NODE_META "$@"
fi
exec docker-entrypoint.sh "${@}"
