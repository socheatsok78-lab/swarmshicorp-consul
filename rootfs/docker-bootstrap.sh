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
if [[ -z "${CONSUL_BIND}" ]] && [[ -z "$CONSUL_BIND_INTERFACE" ]]; then
    if [[ -n "${CONSUL_BIND_ADDRESS}" ]]; then
        CONSUL_BIND="-bind=$CONSUL_BIND_ADDRESS"
        echo "==> The CONSUL_BIND_INTERFACE is not set, using address '$CONSUL_BIND_ADDRESS' for bind option..."
    fi
fi
if [[ -z "${CONSUL_CLIENT}" ]] && [[ -z "$CONSUL_CLIENT_INTERFACE" ]]; then
    if [[ -n "${CONSUL_CLIENT_ADDRESS}" ]]; then
        CONSUL_CLIENT="-client=$CONSUL_CLIENT_ADDRESS"
        echo "==> The CONSUL_CLIENT_INTERFACE is not set, using address '$CONSUL_CLIENT_ADDRESS' for client option..."
    fi
fi

# Advertise Address Options
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

# DNS and Domain Options
if [[ -n "${CONSUL_DNS_PORT}" ]]; then
    docker_bootstrap_set_arg "-dns-port=${CONSUL_DNS_PORT}"
fi
if [[ -n "${CONSUL_DNS_DOMAIN}" ]]; then
    docker_bootstrap_set_arg "-domain=${CONSUL_DNS_DOMAIN}"
fi
if [[ -n "$CONSUL_DNS_ALT_DOMAIN" ]]; then
    docker_bootstrap_set_arg "-alt-domain=${CONSUL_DNS_ALT_DOMAIN}"
fi
if [[ -n "$CONSUL_DNS_RECURSOR" ]]; then
    docker_bootstrap_set_arg "-recursor=${CONSUL_DNS_RECURSOR}"
fi

# Extra Options
if [[ -z "${CONSUL_LOG_LEVEL}" ]]; then
    CONSUL_LOG_LEVEL="INFO"
fi
docker_bootstrap_set_arg "-log-level=${CONSUL_LOG_LEVEL}"

# run the original entrypoint
if [ "$1" = 'agent' ]; then
    set -- "$@" $CONSUL_BIND $CONSUL_CLIENT $CONSUL_ADVERTISE $CONSUL_ADVERTISE_WAN $DOCKER_BOOTSTRAP_ARGS
fi
exec docker-entrypoint.sh "${@}"
