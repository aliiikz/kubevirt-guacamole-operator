#!/bin/bash

# Deploy KubeVirt-Guacamole Monitoring Stack
# This script deploys a comprehensive monitoring solution for analyzing
# network traffic differences between RDP and VNC protocols

set -e

echo "🚀 Deploying KubeVirt-Guacamole Monitoring Stack..."

# Apply monitoring components in order
echo "📁 Creating monitoring namespace and RBAC..."
kubectl apply -f 01-namespace-rbac.yaml

echo "⚙️  Configuring Prometheus..."
kubectl apply -f 02-prometheus-config.yaml

echo "📊 Deploying Prometheus..."
kubectl apply -f 03-prometheus.yaml

echo "📈 Deploying Node Exporter..."
kubectl apply -f 04-node-exporter.yaml

echo "📋 Configuring Grafana..."
kubectl apply -f 05-grafana-config.yaml

echo "📊 Deploying Grafana..."
kubectl apply -f 06-grafana.yaml

echo "⏳ Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pod -l app=prometheus -n monitoring --timeout=300s
kubectl wait --for=condition=Ready pod -l app=grafana -n monitoring --timeout=300s

echo ""
echo "✅ Monitoring stack deployed successfully!"
echo ""
echo "🌐 Access URLs:"
echo "  📊 Grafana:    http://localhost:30300 (admin/admin)"
echo "  📈 Prometheus: http://localhost:30090"
echo ""
echo "📋 Pre-configured Dashboards:"
echo "  • RDP vs VNC Network Traffic Comparison"
echo "  • VM Performance Dashboard"
echo "  • Operator Health Dashboard"
echo ""
echo "🔍 Key Metrics for Analysis:"
echo "  • container_network_transmit_bytes_total{pod=~\"virt-launcher-vm.*\"}"
echo "  • container_network_receive_bytes_total{pod=~\"virt-launcher-vm.*\"}"
echo "  • Rate calculations for bandwidth comparison"
echo ""
echo "📊 Sample PromQL Queries:"
echo "  # Total network traffic by VM"
echo "  sum(rate(container_network_transmit_bytes_total{pod=~\"virt-launcher-vm.*\"}[5m]) + rate(container_network_receive_bytes_total{pod=~\"virt-launcher-vm.*\"}[5m])) by (pod)"
echo ""
echo "  # Compare bandwidth between VMs"
echo "  rate(container_network_transmit_bytes_total{pod=\"virt-launcher-vm1-xyz\"}[5m]) vs rate(container_network_transmit_bytes_total{pod=\"virt-launcher-vm2-xyz\"}[5m])"
echo ""
echo "💡 To analyze RDP vs VNC performance:"
echo "  1. Ensure VMs have protocol labels/annotations"
echo "  2. Use VM1 (RDP) and VM2 (VNC) for comparison"
echo "  3. Monitor network metrics during typical usage scenarios"
echo "  4. Export data from Grafana for detailed analysis"
echo ""
echo "🔧 Troubleshooting:"
echo "  kubectl logs -n monitoring deployment/prometheus"
echo "  kubectl logs -n monitoring deployment/grafana"
echo "  kubectl get pods -n monitoring"
