#!/bin/bash
# For Ubuntu 22.04 - Worker Node Installation ONLY

set -e
set -x

# Log all output
exec > >(tee /var/log/worker-init-script.log) 2>&1
echo "Starting WORKER NODE initialization..."

# 1. SYSTEM SETUP (same as control plane)
sudo apt update && sudo apt upgrade -y
sudo apt install -y apt-transport-https ca-certificates curl

# 2. DISABLE SWAP
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# 3. KERNEL MODULES
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# 4. NETWORK CONFIG
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# 5. CONTAINERD SETUP
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# 6. KUBERNETES PACKAGES
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo tee /etc/apt/trusted.gpg.d/kubernetes.asc
echo "deb https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# 7. PATH CONFIGURATION
echo "export PATH=\$PATH:/usr/bin" >> /etc/profile.d/k8s.sh
chmod +x /etc/profile.d/k8s.sh

# 8. INSTRUCTIONS FOR MANUAL JOIN
echo "Worker node initialized." > /home/ubuntu/join-instructions.txt
echo "To join cluster, SSH into control plane and:" >> /home/ubuntu/join-instructions.txt
echo "1. Get join command: cat /home/ubuntu/join-command.txt" >> /home/ubuntu/join-instructions.txt
echo "2. Run it on this worker node" >> /home/ubuntu/join-instructions.txt
chown ubuntu:ubuntu /home/ubuntu/join-instructions.txt

echo "Worker node initialized. Now manually join it using the command from control plane."