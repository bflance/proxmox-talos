#!/bin/bash

# Proxmox variables
CLUSTER_NAME=my-talos
PROXMOX_NODE="pve"
TALOS_ISO="local:iso/talos.iso"
DISK_STORAGE="local-lvm"
DISK_SIZE="20"
RAM_SIZE="4096"
CPU_CORES="4"
NUMBER_OF_VMS=3
TALOS_VERSION=v1.9.2

# Function to check if talosctl is installed, and install it if not
install_talosctl() {
  if ! command -v talosctl &>/dev/null; then
    echo "talosctl not found. Installing..."
    curl -LO https://github.com/siderolabs/talos/releases/download/$TALOS_VERSION/talosctl-linux-amd64
    chmod +x talosctl-linux-amd64
    mv talosctl-linux-amd64 /usr/local/bin/talosctl
    echo "talosctl installed successfully."
  else
    echo "talosctl is already installed."
  fi
}

# Function to check if talosctl is installed, and install it if not
install_talosctl


check_and_download_talos_iso() {
  local ISO_PATH="/var/lib/vz/template/iso/talos.iso"
  local ISO_URL="https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/$TALOS_VERSION/metal-amd64.iso"

  if [ ! -f "$ISO_PATH" ]; then
    echo "ISO not found, downloading..."
    mkdir -p "$(dirname "$ISO_PATH")"
    wget -O "$ISO_PATH" "$ISO_URL"
    if [ $? -eq 0 ]; then
      echo "ISO downloaded successfully."
    else
      echo "Failed to download ISO."
    fi
  else
    echo "ISO already exists."
  fi
}

check_and_download_talos_iso

create_vms() {
    local vm_count=${NUMBER_OF_VMS}
    local base_vm_id=900
    
    for i in $(seq 1 $vm_count); do
        local vm_id=$((base_vm_id + i))
        local vm_name="$CLUSTER_NAME-node-$i"
        echo "Creating VM $vm_name with ID $vm_id..."

        if qm status $vm_id &>/dev/null; then
            echo "VM $vm_name (ID $vm_id) already exists. Skipping creation."
        else
            qm create $vm_id \
                --name $vm_name \
                --memory $RAM_SIZE \
                --cores $CPU_CORES \
                --cpu cputype=host \
                --boot order=ide2 \
                --ostype l26 \
                --agent enabled=1 \
                --scsihw virtio-scsi-pci \
                --scsi0 file=$DISK_STORAGE:$DISK_SIZE \
                --net0 "virtio=BC:24:11:4B:5D:C$i",bridge=vmbr0 \
                --ide2 $TALOS_ISO,media=cdrom \
                --onboot yes
        fi

        echo "Starting VM $vm_name..."
        qm start $vm_id
    done

    echo "All VMs created. Now proceeding with Talos cluster deployment."
}

delete_vms() {
    local base_vm_id=900
    local vm_count=${NUMBER_OF_VMS}
    
    for i in $(seq 1 $vm_count); do
        local vm_id=$((base_vm_id + i))
        echo "Stopping VM $vm_id if running..."
        qm stop $vm_id --skiplock 2>/dev/null
        
        echo "Destroying VM $vm_id..."
        qm destroy $vm_id --skiplock 2>/dev/null
    done

    echo "All VMs with IDs from $base_vm_id to $((base_vm_id + vm_count)) have been deleted."
}

deploy_talos_cluster() {
    mkdir -p myTalosCluster && cd myTalosCluster
    echo "Waiting for VMs to get IP addresses..."
    local sleep_interval=5
    local all_ips_found=false
    
    while true; do
        CONTROL_PLANE_IP=$(qm guest cmd 901 network-get-interfaces | grep "ip-address" | awk -F'"' '{print $4}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -v 127.0.0.1 | grep -v 169.254)
        WORKER_IPS=()
        
        for i in $(seq 2 $NUMBER_OF_VMS); do
            WORKER_IPS+=($(qm guest cmd $((900 + i)) network-get-interfaces | grep "ip-address" | awk -F'"' '{print $4}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -v 127.0.0.1))
        done
        
        # Check if CONTROL_PLANE_IP is found and the number of WORKER_IPS matches the expected number of workers
        if [ -n "$CONTROL_PLANE_IP" ] && [ ${#WORKER_IPS[@]} -eq $((NUMBER_OF_VMS - 1)) ]; then
            all_ips_found=true
            break
        fi
        
        echo "Waiting for IPs..."
        sleep $sleep_interval
    done

    echo "Control Plane IP: $CONTROL_PLANE_IP"
    echo "Worker IPs: ${WORKER_IPS[*]}"
    sleep 5

    talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 --force \
    --install-image factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:$TALOS_VERSION

    ## allow controlplane to become a workernode too
    # echo '    allowSchedulingOnControlPlanes: true' >> controlplane.yaml
    sed -i '/^cluster:/a \ \ \ \ allowSchedulingOnControlPlanes: true' controlplane.yaml

    # talosctl config node $CONTROL_PLANE_IP
    
    while ! nc -zv $CONTROL_PLANE_IP 50000 2>/dev/null; do sleep 5 ;done
    sleep 3

    talosctl apply-config --insecure --nodes $CONTROL_PLANE_IP --file controlplane.yaml
    
    sleep 20
    while ! nc -zv $CONTROL_PLANE_IP 50000 2>/dev/null; do sleep 5 ;done
 
    export TALOSCONFIG="talosconfig"
    talosctl config endpoint $CONTROL_PLANE_IP
    talosctl bootstrap -n $CONTROL_PLANE_IP
    talosctl kubeconfig . -n $CONTROL_PLANE_IP --force
    echo '###### KUBECONFIG FILE ##############'
    cat kubeconfig
    echo '#####################################'
    echo "Talos Cluster bootstrap completed."

    ####### Add nodes
    for node in ${WORKER_IPS[*]}; do
        talosctl apply-config --insecure --nodes $node --file controlplane.yaml #worker.yaml
    done
}

if [[ "$1" == "--delete" ]]; then
    delete_vms
else
    create_vms
    deploy_talos_cluster
fi
