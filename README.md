# proxmox-talos
a scripts and tools to easily deploy talos cluster on proxmox

[![YouTube](http://i.ytimg.com/vi/G3u8GwulKaA/hqdefault.jpg)](https://www.youtube.com/watch?v=G3u8GwulKaA)

### Requisites
- make sure you have SSH password-less access to your proxmox server.\
To do that run this: \
  `ssh-copy-id root@<proxmox-server-ip>`
- Edit `talos-proxmox-manager.sh` script variables for desired cluster resources
- Edit `redeploy.sh` file with your proxmox host IP.
- NOTE: `talos-proxmox-manager.sh` scirpt has some `--config-patch @patches/16-config-mirrors.yaml` arguments baked in,
feel free to remove it if you dont use docker caching proxy repository.
if you want to use it, check this guide: https://www.talos.dev/v1.9/talos-guides/configuration/pull-through-cache/ or read below.
- in `helmfile.yaml` edit `mydomain.net` domains to domain names proper for your setting.

Quick note:
if you want to create mirrors, simply create a VM , or use some ubuntu machine on your netowkr (in my example, i used 192.168.0.41)
then run this on it:

```
apt-get update && apt-get install -y docker.io
docker run -d -p 5000:5000 -e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io --restart always --name registry-docker.io registry:2
docker run -d -p 5001:5000 -e REGISTRY_PROXY_REMOTEURL=https://registry.k8s.io      --restart always --name registry-registry.k8s.io registry:2
docker run -d -p 5003:5000 -e REGISTRY_PROXY_REMOTEURL=https://gcr.io               --restart always --name registry-gcr.io registry:2
docker run -d -p 5004:5000 -e REGISTRY_PROXY_REMOTEURL=https://ghcr.io              --restart always --name registry-ghcr.io registry:2
docker run -d -p 5005:5000 -e REGISTRY_PROXY_REMOTEURL=https://quay.io              --restart always --name registry-quay.io registry:2
```
this will create mirrors to all these repositories, so each time you spin up your cluster, a copy of docker images will be chaced on mirrors,
and you wont get rate-limit error from docker.io or other repositories.

- SECURE_BOOT - please edit export `SECURE_BOOT=false` variable to true if you want your cluster to enable secureboot.
  this will also encrypt the disks with LUKS encryption, using TPM as encryption device (virtual vTPM), if you want/need a real TPM.
  please check how to pass-thru TPM from your machine into proxmox (not tested, to be added as a feature in future...)
  check `talos-proxmox-manager.sh` if you want to encrypt with passphrase instead.



### Create talos cluster on proxmox
```bash
cat talos-proxmox-manager.sh | ssh root@<proxmox-ip>  'bash -s -- --create'
```

### Start talos cluster 
```bash
cat talos-proxmox-manager.sh | ssh root@<proxmox-ip>  'bash -s -- --start'
```

### Stop talos cluster
```bash
cat talos-proxmox-manager.sh | ssh root@<proxmox-ip>  'bash -s -- --stop'
```
### Delete talos cluster
```bash
cat talos-proxmox-manager.sh | ssh root@<proxmox-ip>  'bash -s -- --delete'
```

### re-deploy talos cluster
If you wan to constantly re-deploy (delete and deploy) same cluster, simply run this script

```bash
./redeploy.sh
```

## Using the cluster
Once cluster was deployed, copy over the kubeconfig to your laptop, ex:

```
scp root@$<proxmox-ip>:/.kube/config ~/.kube/talos-kubeconfig"
```
then export new configuration
```
export KUBECONFIG=~/.kube/talos-kubeconfig
```

Enjoy
```
kubectl get nodes
NAME            STATUS   ROLES           AGE   VERSION
talos-jxr-ah2   Ready    control-plane   66m   v1.32.0
talos-kfx-5s8   Ready    control-plane   66m   v1.32.0
talos-lyn-m2s   Ready    control-plane   66m   v1.32.0
```

## Upgrading kubernetes version on cluster

This will upgrade kubernetes version to 1.32.1.\
If you want just latest, remove the `--to 1.32.1`\
(not recommended, always check versions and compatability!)

```
talosctl -n <one-of-nodes> upgrade-k8s --dry-run --to 1.32.1
```
if all good, run this
```
talosctl -n <one-of-nodes> upgrade-k8s --to 1.32.1
```

## Upgrade talos nodes OS version
To upgrade talos node, please run this:\
This will upgrade nodes to version 1.9.3
```
talosctl upgrade --nodes 10.20.30.40 --image ghcr.io/siderolabs/installer:v1.9.3
```
**_NOTE:_** 
Dont forget to update talosctl utility on your laptop
```
brew update talosctl
```
or check this: https://www.talos.dev/v1.9/talos-guides/install/talosctl/
