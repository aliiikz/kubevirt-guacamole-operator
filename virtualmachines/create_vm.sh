#!/bin/bash

set -e

VM_DIR="/home/aliii/Programming/KubeBuilderProject/virtualmachines"

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <datavolume_yml> <vm_yml>"
    echo "Example: $0 dv_ubuntu2.yml vm2_pvc.yml"
    exit 1
fi

DV_FILE="$1"
VM_FILE="$2"
DV_PATH="$VM_DIR/$DV_FILE"
VM_PATH="$VM_DIR/$VM_FILE"

# Validate files
if [ ! -f "$DV_PATH" ]; then
    echo "DataVolume file not found: $DV_PATH"
    exit 1
fi

if [ ! -f "$VM_PATH" ]; then
    echo "VirtualMachine file not found: $VM_PATH"
    exit 1
fi

# Extract names
PVC_NAME="${DV_FILE%.yml}"
PVC_NAME="${PVC_NAME#dv_}"

VM_NAME="${VM_FILE%_pvc.yml}"

### Create DataVolume only if it doesn't exist
echo "Checking if DataVolume '$PVC_NAME' already exists..."
if kubectl get dv "$PVC_NAME" >/dev/null 2>&1; then
    echo "DataVolume '$PVC_NAME' already exists. Skipping creation."
else
    echo -e "\n=================================================="
    echo "Creating DataVolume from $DV_FILE..."
    sudo kubectl create -f "$DV_PATH"
    echo "DataVolume $DV_FILE created, waiting..."
    sleep 10
    echo "PVC is ready!"
fi

### Wait for PVC to be Bound
# echo "Waiting for PVC '$PVC_NAME' to become Bound..."
# for i in {1..60}; do
#     STATUS=$(kubectl get pvc "$PVC_NAME" -o jsonpath="{.status.phase}" 2>/dev/null || echo "NotFound")
#     echo "Status: $STATUS"
#     if [ "$STATUS" = "Bound" ]; then
#         echo "PVC is ready!"
#         break
#     fi
#     sleep 3
# done

# if [ "$STATUS" != "Bound" ]; then
#     echo "PVC '$PVC_NAME' is not ready after timeout. Aborting."
#     exit 1
# fi

### Create VirtualMachine only if it doesn't exist
echo -e "\n=================================================="
echo "Checking if Virtual Machine '$VM_NAME' already exists..."
if kubectl get vm "$VM_NAME" >/dev/null 2>&1; then
    echo "VirtualMachine '$VM_NAME' already exists. Skipping creation."
else
    echo "Creating Virtual Machine from $VM_FILE..."
    sudo kubectl create -f "$VM_PATH"
fi

### Wait for IP
echo -e "\n=================================================="
echo "Waiting for VM '$VM_NAME' to receive an IP..."
for i in {1..60}; do
    sleep 3
    IP=$(kubectl get vmis "$VM_NAME" -o jsonpath="{.status.interfaces[0].ipAddress}" 2>/dev/null || echo "")
    if [ -n "$IP" ]; then
        echo "VM '$VM_NAME' has IP: $IP"
        break
    else
        echo "Attempt $i: No IP assigned yet..."
    fi
done

### Final report
echo -e "\n=================================================="
echo "Final VM status:"
kubectl get vmis -o wide
