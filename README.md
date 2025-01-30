# proxmox-talos
a scripts and tools to easily deploy talos cluster on proxmox

### Dploy talos cluster on proxmox
```bash
cat talos-proxmox-manager.sh | ssh root@<proxmox-ip>  'bash -s --'
```

### Delete talos cluster from proxmox
```bash
cat talos-proxmox-manager.sh | ssh root@<proxmox-ip>  'bash -s -- --delete'
```