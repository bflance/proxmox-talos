#!/bin/bash
export PROXMOX_HOST=192.168.0.20
export KUBECONFIG=~/.kube/talos-config

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

cat talos-proxmox-manager.sh | ssh root@$PROXMOX_HOST  'bash -s -- --delete'
sleep 1
cat talos-proxmox-manager.sh | ssh root@$PROXMOX_HOST  'bash -s -- --create'
rm -rf ~/.kube/talos-config

scp root@$PROXMOX_HOST:~/.kube/config ~/.kube/talos-config &>/dev/null
scp root@$PROXMOX_HOST:~/.talos/config ~/.talos/config     &>/dev/null
scp -r root@$PROXMOX_HOST:myTalosCluster .                 &>/dev/null

echo -e "${BLUE}[$(date +%Y-%m-%d.%H:%M:%S)]${NC} Running helmfile"

helmfile sync --skip-deps --selector name=metallb
helmfile sync --skip-deps
