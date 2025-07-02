#!/bin/bash

set -e

echo "🚀 Deploying Monitoring Stack..."

echo "Creating monitoring namespace and RBAC..."
kubectl apply -f 01-namespace-rbac.yaml

echo "Setting up persistent storage..."
kubectl apply -f persistent-storage.yaml

echo "Generating and configuring Prometheus..."
./generate-config.sh
kubectl apply -f 02-prometheus-config.yaml

echo "Deploying Prometheus..."
kubectl apply -f 03-prometheus.yaml

echo "Deploying Node Exporter..."
kubectl apply -f 04-node-exporter.yaml

echo "Configuring Grafana..."
kubectl apply -f 05-grafana-config.yaml

echo "Deploying Grafana..."
kubectl apply -f 06-grafana.yaml

echo "Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pod -l app=prometheus -n monitoring --timeout=300s
kubectl wait --for=condition=Ready pod -l app=grafana -n monitoring --timeout=300s

echo ""
echo "Monitoring stack deployed successfully!"
echo ""