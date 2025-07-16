#!/bin/bash

# Simple IP detection using hostname -I
export NODE_IP=$(hostname -I | awk '{print $1}')

# Validate IP
if [[ -z "$NODE_IP" || ! "$NODE_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "Error: Could not detect valid IP address" >&2
    exit 1
fi

# Export all environment variables
export GUACAMOLE_PORT="30080"
export KEYCLOAK_PORT="30081"
export GRAFANA_PORT="30300"
export PROMETHEUS_PORT="30090"

# Composite endpoints
export GUACAMOLE_ENDPOINT="${NODE_IP}:${GUACAMOLE_PORT}"
export KEYCLOAK_ENDPOINT="${NODE_IP}:${KEYCLOAK_PORT}"
export GRAFANA_ENDPOINT="${NODE_IP}:${GRAFANA_PORT}"
export PROMETHEUS_ENDPOINT="${NODE_IP}:${PROMETHEUS_PORT}"

echo "Detected Node IP: $NODE_IP"
echo "Guacamole Endpoint: $GUACAMOLE_ENDPOINT"
echo "Keycloak Endpoint: $KEYCLOAK_ENDPOINT"
echo "Grafana Endpoint: $GRAFANA_ENDPOINT"
echo "Prometheus Endpoint: $PROMETHEUS_ENDPOINT"
