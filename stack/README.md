# KubeVirt Guacamole Auto-Connect Operator

The Kubernetes Operator dynamically provisions Apache Guacamole connections for newly created VMs managed by KubeVirt.

## How It Works

1. The operator listens for `VirtualMachineInstance` (`VMI`) creation events via the Kubernetes API.

2. When a new VM is detected:

- VM metadata (IP, name, etc.) is extracted.
- A REST API call is made to Guacamole to create a new connection with appropriate parameters.

3. When the user accesses the Guacamole UI:

- Upon successful login, they are presented with the dynamically created connection(s) for their VM(s).
