# Monitoring Stack for KubeVirt-Guacamole Operator

This monitoring stack provides comprehensive observability for the KubeVirt-Guacamole operator system, with a focus on network traffic analysis between RDP and VNC connections.

## 🎯 Monitoring Goals

- **Network Traffic Analysis**: Compare bandwidth usage between RDP vs VNC protocols
- **Performance Metrics**: Monitor VM performance, connection latency, and resource usage
- **System Health**: Track operator health, Guacamole performance, and cluster metrics
- **Connection Analytics**: Monitor active connections, session duration, and user activity

## 🛠️ Stack Components

### Core Monitoring
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **Node Exporter**: Host-level metrics
- **cAdvisor**: Container metrics (built into kubelet)

### Network Monitoring
- **Node Exporter**: Network interface metrics and host-level monitoring
- **VM Network Metrics**: Per-VM network statistics via cAdvisor
- **Container Metrics**: Network traffic analysis per container

## 📊 Key Metrics for RDP vs VNC Analysis

### Network Metrics
- `node_network_receive_bytes_total` - Incoming network traffic per interface
- `node_network_transmit_bytes_total` - Outgoing network traffic per interface
- `container_network_receive_bytes_total` - Container-level network metrics
- `container_network_transmit_bytes_total` - Container-level network metrics

### VM-Specific Metrics
- `kubevirt_vmi_network_receive_bytes_total` - VM network incoming
- `kubevirt_vmi_network_transmit_bytes_total` - VM network outgoing
- `kubevirt_vmi_network_receive_packets_total` - VM packet counts
- `kubevirt_vmi_network_transmit_packets_total` - VM packet counts

### Connection Metrics
- Guacamole active connections by protocol
- Session duration metrics
- Connection establishment time
- Protocol-specific bandwidth usage

## 🚀 Quick Start

1. **Deploy the monitoring stack:**
   ```bash
   kubectl apply -f monitoring/
   ```

2. **Access dashboards:**
   - Grafana: http://localhost:30300 (admin/admin)
   - Prometheus: http://localhost:30090

3. **Import pre-built dashboards:**
   - Network Traffic Comparison Dashboard
   - VM Performance Dashboard

## 📈 Analysis Approach

### Network Traffic Comparison
1. **Baseline Measurement**: Establish baseline network usage for idle VMs
2. **Protocol Testing**: 
   - Create identical workloads on RDP and VNC VMs
   - Measure network traffic during typical usage scenarios
   - Compare bandwidth efficiency between protocols

3. **Metrics Collection**:
   - Use VM labels to differentiate protocol types
   - Query time-series data for network bytes transferred
   - Calculate average bandwidth per connection type

### Sample PromQL Queries
```promql
# RDP VM network traffic (last 5 minutes)
rate(kubevirt_vmi_network_transmit_bytes_total{protocol="rdp"}[5m])

# VNC VM network traffic (last 5 minutes)  
rate(kubevirt_vmi_network_transmit_bytes_total{protocol="vnc"}[5m])

# Bandwidth comparison
sum(rate(kubevirt_vmi_network_transmit_bytes_total[5m])) by (protocol)
```

## 🎛️ Dashboard Features

### Network Analysis Dashboard
- Real-time bandwidth usage by protocol
- Historical comparison charts
- Network efficiency metrics
- Connection-specific traffic analysis

### VM Performance Dashboard
- CPU and memory usage per VM
- Storage I/O metrics
- Network latency measurements
- Resource utilization trends

### Operator Health Dashboard
- Operator reconciliation metrics
- Guacamole API response times
- Error rates and success ratios
- Connection establishment metrics

## 🔧 Configuration

All monitoring components are configured via Kubernetes manifests with:
- Service discovery for automatic metric collection
- Persistent storage for historical data
- High availability setup for production use
- Security configurations and RBAC

## 📝 Usage Notes

- Metrics are retained for 30 days by default
- Dashboards auto-refresh every 30 seconds
- Network traffic is measured in bytes/second
- All timestamps are in UTC
- Export data via Grafana for detailed analysis
