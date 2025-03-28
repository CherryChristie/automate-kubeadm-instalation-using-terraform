#!/bin/bash
# For Ubuntu 22.04 - Control Plane Installation

set -e
set -x

# Log all output
exec > >(tee /var/log/control-init-script.log) 2>&1
echo "Starting CONTROL PLANE initialization..."

# 1. SYSTEM SETUP
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

# 7. INITIALIZE CLUSTER (CRITICAL FIX)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --apiserver-advertise-address=$PRIVATE_IP \
  --control-plane-endpoint=$PRIVATE_IP

# 8. CONFIGURE KUBECONFIG
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 9. INSTALL NETWORK PLUGIN
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# 10. GENERATE WORKER JOIN COMMAND
JOIN_COMMAND=$(kubeadm token create --print-join-command)
echo "WORKER JOIN COMMAND:" > /home/ubuntu/join-command.txt
echo "$JOIN_COMMAND" >> /home/ubuntu/join-command.txt
chown ubuntu:ubuntu /home/ubuntu/join-command.txt

# 11. PATH CONFIGURATION
echo "export PATH=\$PATH:/usr/bin" >> /etc/profile.d/k8s.sh
chmod +x /etc/profile.d/k8s.sh

echo "Control plane initialization completed successfully!"
echo "Worker join command saved to /home/ubuntu/join-command.txt"