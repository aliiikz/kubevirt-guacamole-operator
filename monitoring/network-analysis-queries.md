# Network Traffic Analysis Queries for RDP vs VNC Comparison

## Core Network Metrics

### 1. VM Network Traffic (Bytes per second)
```promql
# Outbound traffic per VM
rate(container_network_transmit_bytes_total{pod=~"virt-launcher-vm.*"}[5m])

# Inbound traffic per VM  
rate(container_network_receive_bytes_total{pod=~"virt-launcher-vm.*"}[5m])

# Total traffic per VM
rate(container_network_transmit_bytes_total{pod=~"virt-launcher-vm.*"}[5m]) + 
rate(container_network_receive_bytes_total{pod=~"virt-launcher-vm.*"}[5m])
```

### 2. Protocol Comparison (Assuming VM1=RDP, VM2=VNC)
```promql
# RDP VM traffic (VM1)
sum(rate(container_network_transmit_bytes_total{pod=~"virt-launcher-vm1.*"}[5m]) + 
    rate(container_network_receive_bytes_total{pod=~"virt-launcher-vm1.*"}[5m]))

# VNC VM traffic (VM2) 
sum(rate(container_network_transmit_bytes_total{pod=~"virt-launcher-vm2.*"}[5m]) + 
    rate(container_network_receive_bytes_total{pod=~"virt-launcher-vm2.*"}[5m]))

# Bandwidth efficiency comparison (RDP vs VNC)
(
  sum(rate(container_network_transmit_bytes_total{pod=~"virt-launcher-vm1.*"}[5m]) + 
      rate(container_network_receive_bytes_total{pod=~"virt-launcher-vm1.*"}[5m]))
) / (
  sum(rate(container_network_transmit_bytes_total{pod=~"virt-launcher-vm2.*"}[5m]) + 
      rate(container_network_receive_bytes_total{pod=~"virt-launcher-vm2.*"}[5m]))
)
```

### 3. Packet Analysis
```promql
# Packets per second - RDP
rate(container_network_transmit_packets_total{pod=~"virt-launcher-vm1.*"}[5m]) +
rate(container_network_receive_packets_total{pod=~"virt-launcher-vm1.*"}[5m])

# Packets per second - VNC
rate(container_network_transmit_packets_total{pod=~"virt-launcher-vm2.*"}[5m]) +
rate(container_network_receive_packets_total{pod=~"virt-launcher-vm2.*"}[5m])

# Average packet size comparison
(
  sum(rate(container_network_transmit_bytes_total{pod=~"virt-launcher-vm1.*"}[5m])) /
  sum(rate(container_network_transmit_packets_total{pod=~"virt-launcher-vm1.*"}[5m]))
) vs (
  sum(rate(container_network_transmit_bytes_total{pod=~"virt-launcher-vm2.*"}[5m])) /
  sum(rate(container_network_transmit_packets_total{pod=~"virt-launcher-vm2.*"}[5m]))
)
```

### 4. Historical Analysis
```promql
# Total bytes transferred in last hour - RDP
increase(container_network_transmit_bytes_total{pod=~"virt-launcher-vm1.*"}[1h]) +
increase(container_network_receive_bytes_total{pod=~"virt-launcher-vm1.*"}[1h])

# Total bytes transferred in last hour - VNC
increase(container_network_transmit_bytes_total{pod=~"virt-launcher-vm2.*"}[1h]) +
increase(container_network_receive_bytes_total{pod=~"virt-launcher-vm2.*"}[1h])

# Peak bandwidth usage in last 24h
max_over_time(
  (rate(container_network_transmit_bytes_total{pod=~"virt-launcher-vm.*"}[5m]) +
   rate(container_network_receive_bytes_total{pod=~"virt-launcher-vm.*"}[5m]))[24h:5m]
)
```

### 5. Connection Quality Metrics
```promql
# Network errors
rate(container_network_transmit_errors_total{pod=~"virt-launcher-vm.*"}[5m])
rate(container_network_receive_errors_total{pod=~"virt-launcher-vm.*"}[5m])

# Network drops
rate(container_network_transmit_dropped_total{pod=~"virt-launcher-vm.*"}[5m])
rate(container_network_receive_dropped_total{pod=~"virt-launcher-vm.*"}[5m])
```

## Performance Correlation Queries

### 6. CPU vs Network Usage
```promql
# CPU usage correlation
rate(container_cpu_usage_seconds_total{pod=~"virt-launcher-vm.*"}[5m]) * 100

# Memory usage
container_memory_usage_bytes{pod=~"virt-launcher-vm.*"}

# Network vs CPU correlation
(
  rate(container_network_transmit_bytes_total{pod=~"virt-launcher-vm.*"}[5m]) +
  rate(container_network_receive_bytes_total{pod=~"virt-launcher-vm.*"}[5m])
) * on(pod) group_left() (
  rate(container_cpu_usage_seconds_total{pod=~"virt-launcher-vm.*"}[5m])
)
```

## Alert Rules for Protocol Comparison

### 7. High Bandwidth Usage
```promql
# Alert when VM bandwidth exceeds 10MB/s
(
  rate(container_network_transmit_bytes_total{pod=~"virt-launcher-vm.*"}[5m]) +
  rate(container_network_receive_bytes_total{pod=~"virt-launcher-vm.*"}[5m])
) > 10485760  # 10MB/s in bytes
```

### 8. Protocol Efficiency Monitoring
```promql
# Alert when RDP uses 50% more bandwidth than VNC
(
  sum(rate(container_network_transmit_bytes_total{pod=~"virt-launcher-vm1.*"}[5m])) /
  sum(rate(container_network_transmit_bytes_total{pod=~"virt-launcher-vm2.*"}[5m]))
) > 1.5
```

## Usage Instructions

1. **Baseline Measurement**: Run these queries when VMs are idle to establish baseline
2. **Load Testing**: Create identical workloads on both VMs and compare metrics
3. **Real-time Monitoring**: Use 5m rate calculations for real-time analysis
4. **Historical Analysis**: Use increase() functions for cumulative measurements
5. **Export Data**: Use Grafana's export functionality to get raw data for analysis

## Expected Results

- **RDP**: Generally higher bandwidth due to richer graphics and audio
- **VNC**: More efficient for simple desktop operations
- **Packet Size**: RDP typically uses larger packets
- **CPU Correlation**: Graphics-intensive operations show higher correlation

## VNC Setup Notes
### Managing VNC Server
```bash
# Kill current VNC session
vncserver -kill :0
vncserver -kill :1

# Check running VNC sessions
vncserver -list

# Start VNC manually (if not using service)
vncserver :0 -geometry 1920x1080 -depth 24 -localhost no

## When using another display like :1, the port for VNC changes from 5900 to 5901
vncserver :1 -geometry 1920x1080 -depth 24 -localhost no


# View VNC logs
cat ~/.vnc/*.log
```

- VNC Password is set to `vm2test`

# Check Ports
```bash
# Verify VNC is accessible externally
sudo netstat -tlnp | grep 5901

# Test local connection first
ss -tuln | grep 5901
```

