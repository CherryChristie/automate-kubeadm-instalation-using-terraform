#!/bin/bash
# For Ubuntu 22.04 - Worker Node Installation

set -e # Exit script immediately on first error.
set -x # Print commands and their arguments as they are executed.

# Log all output to file
exec > >(tee /var/log/worker-init-script.log) 2>&1

echo "Starting worker node initialization script..."

# Update system
sudo apt update && sudo apt upgrade -y
sudo apt install -y apt-transport-https ca-certificates curl

sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

sudo apt install -y containerd

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml


/etc/containerd/config.toml and set SystemdCgroup = true:

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml


sudo systemctl restart containerd
sudo systemctl enable containerd

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo tee /etc/apt/trusted.gpg.d/kubernetes.asc
echo "deb https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl




mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

echo "Worker node initialization completed successfully!"
# Add Kubernetes binaries to PATH for all users
echo "export PATH=$PATH:/usr/bin" >> /etc/profile.d/k8s.sh
chmod +x /etc/profile.d/k8s.sh