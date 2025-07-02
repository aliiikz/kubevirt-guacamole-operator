#!/bin/bash

echo "Creating Prometheus ConfigMap from external files..."

kubectl create configmap prometheus-config \
  --from-file=prometheus.yml=prometheus.yml \
  --namespace=monitoring \
  --dry-run=client -o yaml > 02-prometheus-config.yaml

