#!/bin/bash

set -e

echo "Removing Monitoring Stack..."

# Remove components in reverse order
echo " Removing Grafana..."
kubectl delete -f 06-grafana.yaml --ignore-not-found=true

echo "Removing Grafana configs..."
kubectl delete -f 05-grafana-config.yaml --ignore-not-found=true

echo "Removing Node Exporter..."
kubectl delete -f 04-node-exporter.yaml --ignore-not-found=true

echo "Removing Prometheus..."
kubectl delete -f 03-prometheus.yaml --ignore-not-found=true

echo "Removing Prometheus config..."
kubectl delete -f 02-prometheus-config.yaml --ignore-not-found=true

echo "Removing namespace and RBAC..."
kubectl delete -f 01-namespace-rbac.yaml --ignore-not-found=true

echo "Waiting for namespace cleanup..."
kubectl wait --for=delete namespace/monitoring --timeout=60s || true

echo "Monitoring stack cleanup completed!"
