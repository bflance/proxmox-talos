#!/bin/bash

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "dialog command not installed"
    echo install it:
    echo ubuntu: apt-get update && apt-get install -y dialog
    echo macos:  brew install dialog 
fi

while true; do
    CHOICE=$(dialog --clear --title "Talos Proxmox Setup" \
        --menu "Choose an option:" 15 50 5 \
        1 "Create cluster" \
        2 "Start Cluster" \
        3 "Stop Cluster" \
        4 "Delete Cluster" \
        5 "Re-create cluster" \
        6 "Exit" \
        2>&1 >/dev/tty)

    clear
    case $CHOICE in
        1)
            echo "Create cluster"
            # Add VM creation logic here
            cat talos-proxmox-manager.sh | ssh root@192.168.0.20  'bash -s -- --create' 
	        ;;
        2)
            echo "Start Cluster"
            cat talos-proxmox-manager.sh | ssh root@192.168.0.20  'bash -s -- --start' 
            ;;
        3)
            echo "Stop Cluster"
            cat talos-proxmox-manager.sh | ssh root@192.168.0.20  'bash -s -- --stop' 
            ;;
        4)
            echo "Delete Cluster"
            cat talos-proxmox-manager.sh | ssh root@192.168.0.20  'bash -s -- --delete' 
            ;;
        5)
            echo "Re-create Cluster"
            ./redeploy.sh
            ;;
        6)
            echo "Exiting..."
            break
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac

done
