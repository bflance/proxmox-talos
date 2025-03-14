#!/bin/bash
### Set SECURE_BOOT=true , if you want your cluster to be secure booted, otherwise leave it "false"
## For more info, read here: https://www.talos.dev/v1.9/talos-guides/install/bare-metal-platforms/secureboot/
export SECURE_BOOT=false
export CLUSTER_NAME=my-talos
export PROXMOX_NODE="pve"
export DISK_STORAGE="local-zfs"
export DISK_SIZE="100"
export RAM_SIZE="8192"
export CPU_CORES="4"
export NUMBER_OF_VMS=3
export VIP_IP=192.168.0.85
export K8S_VERSION=1.32.0
export ROTATE_SERVER_CERTIFICATE=false   ### enable if you want Kubelet CA certificate rotation, for me it did problems, use at your own risk
export TALOS_VERSION=v1.9.2
export TALOS_CONF_DIR=~/myTalosCluster
export IMAGE_HASH=4c4acaf75b4a51d6ec95b38dc8b49fb0af5f699e7fbd12fbf246821c649b5312
export TALOS_IMAGE=https://factory.talos.dev/image/$IMAGE_HASH/$TALOS_VERSION/metal-amd64.iso
export TALOS_IMAGE_SECURE=https://factory.talos.dev/image/$IMAGE_HASH/$TALOS_VERSION/metal-amd64-secureboot.iso
export TALOSCONFIG=$TALOS_CONF_DIR/talosconfig
export INSTALL_IMAGE=factory.talos.dev/installer/$IMAGE_HASH:$TALOS_VERSION
if [[ "$SECURE_BOOT" == "true" ]]; then
    export TALOS_IMAGE="$TALOS_IMAGE_SECURE"
    export INSTALL_IMAGE=factory.talos.dev/installer-secureboot/$IMAGE_HASH:$TALOS_VERSION
fi

export TALOS_ISO=talos-$(echo "$TALOS_IMAGE" | rev | cut -d / -f 1,2| rev  | tr '/' '-')


# Color definitions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if talosctl is installed, and install it if not
install_talosctl() {
  if ! command -v /usr/local/bin/talosctl-$TALOS_VERSION &>/dev/null; then
    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} talosctl not found. Installing..."
    curl -LO https://github.com/siderolabs/talos/releases/download/$TALOS_VERSION/talosctl-linux-amd64
    chmod +x talosctl-linux-amd64 && mv talosctl-linux-amd64 /usr/local/bin/talosctl-$TALOS_VERSION
    rm -rf /usr/local/bin/talosctl && ln -s /usr/local/bin/talosctl-$TALOS_VERSION /usr/local/bin/talosctl
    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 talosctl installed successfully."
  else
    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 talosctl is already installed."
  fi
}
install_kubectl() {
  if ! command -v kubectl &>/dev/null; then
    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} kubectl not found. Installing..."
    { curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x kubectl && mv kubectl /usr/local/bin/ && kubectl version --client; }
    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 kubectl installed successfully."  
  else
    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 kubectl is already installed."
  fi
}



check_and_download_talos_iso() {
  local ISO_PATH="/var/lib/vz/template/iso/$TALOS_ISO"
  local ISO_URL="$TALOS_IMAGE"

  if [ ! -f "$ISO_PATH" ]; then
    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} ISO not found, downloading..."
    mkdir -p "$(dirname "$ISO_PATH")"
    wget -O "$ISO_PATH" "$ISO_URL"
    if [ $? -eq 0 ]; then
      echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 ISO downloaded successfully."
    else
      echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} Failed to download ISO."
    fi
  else
    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 ISO already exists."
  fi
}

remove_cdrom() {
    local base_vm_id=900
    local vm_count=${NUMBER_OF_VMS}
    for i in $(seq 1 $vm_count); do
        local vm_id=$((base_vm_id + i))
        qm set $vm_id -ide2 media=cdrom,file=none &>/dev/null
    done
}


create_vms() {
    check_and_download_talos_iso
    install_kubectl
    install_talosctl
    local vm_count=${NUMBER_OF_VMS}
    local base_vm_id=900
    
    for i in $(seq 1 $vm_count); do
        local vm_id=$((base_vm_id + i))
        local vm_name="$CLUSTER_NAME-node-$i"
        echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \u2728 Creating VM $vm_name with ID $vm_id"

        if qm status $vm_id &>/dev/null; then
            echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} VM $vm_name (ID $vm_id) already exists. Skipping creation."
        else
            qm create $vm_id \
                --name $vm_name \
                --tags $CLUSTER_NAME,$vm_name \
                --memory $RAM_SIZE \
                --cores $CPU_CORES \
                --cpu cputype=host \
                --boot order="scsi0;ide2" \
                --ostype l26 \
                --agent enabled=1 \
                --scsihw virtio-scsi-pci \
                --scsi0 file=$DISK_STORAGE:$DISK_SIZE \
                --machine q35 \
                --bios ovmf \
                --net0 "virtio=BC:24:11:4B:5D:$(printf %02X $i)",bridge=vmbr0 \
                --ide2 /var/lib/vz/template/iso/$TALOS_ISO,media=cdrom \
                --onboot yes &>/dev/null | grep -v "swtpm"


            # Add Secure Boot settings if SECURE_BOOT=true
            if [[ "$SECURE_BOOT" == "true" ]]; then
              echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xF0\x9F\x94\x90 SECURE_BOOT:ON, Adding vTPM on ${GREEN}$vm_id${NC}"
              qm set $vm_id --efidisk0 $DISK_STORAGE:0,format=raw,efitype=4m,pre-enrolled-keys=0 &>/dev/null
              qm set $vm_id --tpmstate0 $DISK_STORAGE:0,version=v2.0 &>/dev/null
            else
              qm set $vm_id --efidisk0 $DISK_STORAGE:0,format=raw,efitype=4m &>/dev/null
            fi
        fi

cat >> /etc/pve/qemu-server/90$i.conf << "EOF"
#<br>
#<br>
#<br>
#<div align='center'>
#<img src="data:image/png;base64,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" />
#
## Talos Kubernetes Node
#</div>
EOF

        echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xF0\x9F\x9A\x80 Starting VM $vm_name with ID $vm_id"
        qm start $vm_id | grep -v swtpm
    done

    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 All VMs created . Now proceeding with Talos cluster deployment."
}

delete_vms() {
    rm -rf $TALOS_CONF_DIR ~/.talos ~/.kube
    local base_vm_id=900
    local vm_count=${NUMBER_OF_VMS}
    
    for i in $(seq 1 $vm_count); do
        local vm_id=$((base_vm_id + i))
        echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} Stopping VM $vm_id if running..."
        qm stop $vm_id --skiplock 2>/dev/null
        
        echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} Destroying VM $vm_id..."
        qm destroy $vm_id --skiplock 2>/dev/null
    done

    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 All VMs with IDs from $base_vm_id to $((base_vm_id + vm_count)) have been deleted."
}

start_vms() {
    rm -rf $TALOS_CONF_DIR ~/.talos ~/.kube
    local base_vm_id=900
    local vm_count=${NUMBER_OF_VMS}
    
    for i in $(seq 1 $vm_count); do
        local vm_id=$((base_vm_id + i))
        echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} Starting stopped VM $vm_id ..."
        qm start $vm_id --skiplock 2>/dev/null
    done

    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 All VMs with IDs from $base_vm_id to $((base_vm_id + vm_count)) have been started.'\xE2\x9C\x85'"
}



stop_vms() {
    rm -rf $TALOS_CONF_DIR ~/.talos ~/.kube
    local base_vm_id=900
    local vm_count=${NUMBER_OF_VMS}
    
    for i in $(seq 1 $vm_count); do
        local vm_id=$((base_vm_id + i))
        echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} Stopping VM $vm_id if running..."
        qm stop $vm_id --skiplock 2>/dev/null
    done

    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 All VMs with IDs from $base_vm_id to $((base_vm_id + vm_count)) have been stopped.'\xE2\x9C\x85'"
}


prepare_talos_config() {
    mkdir -p $TALOS_CONF_DIR && cd $TALOS_CONF_DIR
    mkdir -p ~/.talos && mkdir -p patches
    local sleep_interval=3
    local all_ips_found=false
    
    while true; do
        export NODE_IPS=()
        for i in $(seq 1 $NUMBER_OF_VMS); do
            NODE_IPS+=($(qm guest cmd $((900 + i)) network-get-interfaces 2>/dev/null | grep "ip-address" | awk -F'"' '{print $4}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -v 127.0.0.1 | grep -v 169.254))
        done              
        if  [ ${#NODE_IPS[@]} -eq $((NUMBER_OF_VMS )) ]; then
            all_ips_found=true
            break
        fi
            echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \u23F3 Waiting for VMs to get IP addresses..."
        sleep $sleep_interval
    done

    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 Worker IPs are: ${GREEN}${NODE_IPS[*]}${NC}"
    sleep 1


cat > patches/1-allow-scheduling-on-cp.yaml << "EOF"
cluster:
  allowSchedulingOnControlPlanes: true
EOF

cat > patches/2-certificate-rotation.yaml << EOF
machine:
  kubelet:
    extraArgs:
      rotate-server-certificates: $ROTATE_SERVER_CERTIFICATE
cluster:
  extraManifests:
    - https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml
EOF

cat > patches/3-interface-names.yaml << "EOF"
machine:
  install:
    extraKernelArgs:
      - net.ifnames=0
EOF
cat > patches/4-ensure-dhcp.yaml << "EOF"
machine:
  network:
    interfaces:
      - interface: eth0
        dhcp: true
EOF
cat > patches/5-vip.yaml << EOF
machine:
  network:
    interfaces:
      - interface: eth0
        vip:
          ip: $VIP_IP
EOF
cat > patches/6-remove-default-cni.yaml << "EOF"
cluster:
  network:
    cni:
      name: none
EOF

cat > patches/7-install-disk.yaml << "EOF"
machine:
    install:
        disk: /dev/sda
EOF

cat > patches/8-enable-kubespan.yaml << "EOF"
machine:
  network:
    kubespan:
      enabled: true
cluster:
  discovery:
    enabled: true
EOF

cat > patches/9-local-path-profisioner.yaml << "EOF"
machine:
  kubelet:
    extraMounts:
      - destination: /var/local-path-provisioner
        type: bind
        source: /var/local-path-provisioner
        options:
          - bind
          - rshared
          - rw
EOF
cat > patches/11-valid-subnets.yaml << "EOF"
machine:
  kubelet:
    nodeIP:
      validSubnets:
        - 192.168.0.0/16
cluster:
  etcd:
    advertisedSubnets: # listenSubnets defaults to advertisedSubnets if not set explicitly
      - 192.168.0.0/16
EOF
cat > patches/12-remove-exclude-from-external-load-balancers-label.yaml << "EOF"
machine:
    nodeLabels:
        node.kubernetes.io/exclude-from-external-load-balancers: ""
        $patch: delete
EOF
cat > patches/13-patch-sans.yaml << EOF
machine:
    certSANs:
      - $VIP_IP
$(for ip in ${NODE_IPS[*]}; do echo "      - $ip"; done)
cluster:
    apiServer:
        certSANs:
$(for ip in ${NODE_IPS[*]}; do echo "          - $ip"; done)
EOF
cat > patches/14-enable-hostdns.yaml << EOF
machine:
  features:
    hostDNS:
      enabled: true
      resolveMemberNames: true
EOF
cat > patches/15-enable-metrics-cp.yaml << EOF
machine:
  kubelet:
    extraArgs:
      rotate-server-certificates: $ROTATE_SERVER_CERTIFICATE
  files:
    - content: |
        [metrics]
          address = "0.0.0.0:11234"
      path: /etc/cri/conf.d/20-customization.part
      op: create
cluster:
  etcd:
    extraArgs:
      listen-metrics-urls: http://0.0.0.0:2381
  controllerManager:
    extraArgs:
      bind-address: 0.0.0.0
  scheduler:
    extraArgs: 
      bind-address: 0.0.0.0
  proxy:
    extraArgs:
      metrics-bind-address: 0.0.0.0:10249
  extraManifests:
    - https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml
    - https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
EOF

cat > patches/15-enable-metrics-wn.yaml << EOF
machine:
  kubelet:
    extraArgs:
      rotate-server-certificates: $ROTATE_SERVER_CERTIFICATE
  files:
    - content: |
        [metrics]
          address = "0.0.0.0:11234"        
      path: /var/cri/conf.d/metrics.toml
      op: create
EOF
cat > patches/16-config-mirrors.yaml << EOF
machine:
    registries:
        mirrors:
            docker.io:
                endpoints:
                    - http://192.168.0.41:5000
            registry.k8s.io:
                endpoints:
                    - http://192.168.0.41:5001
            gcr.io:
                endpoints:
                    - http://192.168.0.41:5003
            ghcr.io:
                endpoints:
                    - http://192.168.0.41:5004
            quay.io:
                endpoints:
                    - http://192.168.0.41:5005 
        config:
            registry.insecure:
                tls:
                    insecureSkipVerify: true
EOF

### tpm - encrypt with the key derived from the TPM (strong, when used with SecureBoot).
cat > patches/17-enable-disk-encryption-tpm.yaml << EOF
machine:
  systemDiskEncryption:
    ephemeral:
      provider: luks2
      keys:
        - slot: 0
          tpm: {}
    state:
      provider: luks2
      keys:
        - slot: 0
          tpm: {}
EOF

### nodeID - encrypt with the key derived from the node UUID 
### (weak, it is designed to protect against data being leaked or recovered from a drive that has been removed from a Talos Linux node).
cat > patches/17-enable-disk-encryption-node-id.yaml << "EOF"
machine:
  systemDiskEncryption:
    ephemeral:
      provider: luks2
      keys:
        - slot: 0
          nodeID: {}
    state:
      provider: luks2
      keys:
        - slot: 0
          nodeID: {}
EOF
cat > patches/18-remove_admission_control.yaml << "EOF"
- op: remove
  path: /cluster/apiServer/admissionControl
EOF

    talosctl gen secrets
    talosctl gen config talos-proxmox-cluster https://$VIP_IP:6443 \
      --kubernetes-version $K8S_VERSION \
      --install-image $INSTALL_IMAGE \
      --config-patch-control-plane '[{"op": "remove", "path": "/cluster/apiServer/admissionControl"}]' \
      --with-kubespan --with-secrets secrets.yaml \
      --config-patch-control-plane @patches/5-vip.yaml \
      --config-patch-control-plane @patches/15-enable-metrics-cp.yaml \
      --config-patch @patches/1-allow-scheduling-on-cp.yaml \
      --config-patch @patches/3-interface-names.yaml \
      --config-patch @patches/4-ensure-dhcp.yaml \
      --config-patch @patches/7-install-disk.yaml \
      --config-patch @patches/9-local-path-profisioner.yaml \
      --config-patch @patches/12-remove-exclude-from-external-load-balancers-label.yaml \
      --config-patch @patches/11-valid-subnets.yaml \
      --config-patch @patches/13-patch-sans.yaml \
      --config-patch @patches/16-config-mirrors.yaml \
      --config-patch @patches/14-enable-hostdns.yaml
      # --config-patch @patches/17-enable-disk-encryption-tpm.yaml \
      # --config-patch @patches/15-enable-metrics-wn.yaml \
      # --config-patch @patches/6-remove-default-cni.yaml \
      # --config-patch @patches/8-enable-kubespan.yaml
      # --config-patch @patches/2-certificate-rotation.yaml \

    talosctl config endpoint ${NODE_IPS[*]}
    talosctl config node ${NODE_IPS[*]}
    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} Talos config contexts:"
    talosctl config contexts
    cp --force $TALOSCONFIG ~/.talos/config
}




bootstrap_talos_cluster(){
    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 Talos Config Folder: $TALOSCONFIG"

    ## apply config for each node  + setup dynamic meaningful hostnames (comment --config-patch if you want defaults)
    for node in ${NODE_IPS[*]}; do
        hostname="node-${node//./-}"  # Replace dots with dashes
        ## check out secure mode settings.
        
        if [[ "$SECURE_BOOT" == "true" ]]; then
            echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xF0\x9F\x94\x90 SECURE_BOOT:ON, checking security on ${GREEN}$hostname${NC}"
            talosctl -n $node -e $node get securitystate --insecure
        fi
        sleep 2
        talosctl apply-config \
            --insecure --nodes $node --file controlplane.yaml \
            --config-patch "[{\"op\": \"replace\", \"path\": \"/machine/network/hostname\", \"value\": \"$hostname\"}]"
        echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 Config was succesfully applied on ${GREEN}$hostname${NC}"
    done
    remove_cdrom

    until $(talosctl bootstrap -n ${NODE_IPS[0]} 2>/dev/null);do 
      echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \U0001F527 Trying to bootstrap talos cluster...";
      sleep 5;
    done
    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 Talos cluster Bootstrapping was ${GREEN}successfull!${NC}";
    sleep 2
    
    until $(talosctl kubeconfig . -n ${NODE_IPS[0]} &>/dev/null);do
      echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \U0001F527 Trying to generate kubeconfig...";
      sleep 2;
    done
    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 Kubeconfig file was created ${GREEN}successfully!${NC}";

    #### WAIT FOR CLUSTER TO GET READY ####
    export NUMBER_OF_MEMBERS=$(talosctl get nodenames | grep Nodename | wc -l)
    export KUBECONFIG=$TALOS_CONF_DIR/kubeconfig
    until $(kubectl get nodes &>/dev/null);do 
      echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \u23F3 Waiting for k8s to be ready"; sleep 5 ; 
    done
    until [ $(kubectl get nodes | awk 'NR>1 && $2=="Ready" {print $2}' | wc -l) -eq $NUMBER_OF_MEMBERS ];do 
      echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \u23F3 Waiting for k8s to be ready" ; kubectl get nodes 2>/dev/null; sleep 3 ; 
    done
    kubectl get nodes &>/dev/null
    echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} \xE2\x9C\x85 K8s cluster is UP"
    ############################################################

    mkdir -p ~/.kube && cp --force kubeconfig ~/.kube/config && chmod 400 ~/.kube/config
    echo 
    echo -e "${YELLOW}     To use your new Talos cluster, please copy the kubeconfig file to your host,exameple:"
    echo
    echo -e "${YELLOW}       scp root@$(hostname -i):$TALOS_CONF_DIR/kubeconfig ~/.kube/talos-kubeconfig"
    echo -e "${YELLOW}       export KUBECONFIG=~/.kube/talos-kubeconfig"
    echo -e "${YELLOW}       kubectl get nodes${NC}"
    echo 
    echo
}

# Help message function
usage() {
    echo "Usage: $0 [--create | --start | --stop | --delete]"
    echo "  --create  Create VMs, configure Talos, and bootstrap cluster"
    echo "  --start   Start stopped VMs"
    echo "  --stop    Stop running VMs"
    echo "  --delete  Delete existing VMs"
    exit 1
}

case "$1" in
    --start)
        start_vms
        ;;
    --stop)
        stop_vms
        ;;
    --delete)
        delete_vms
        ;;
    "--create")
        create_vms
        prepare_talos_config
        bootstrap_talos_cluster
        ;;
    *)
        echo "Error: Unknown argument '$1'"
        usage
        ;;
esac