#!/bin/bash

# disable swap manually
swapoff -a

# to disable swap permanently comment out /swap.img line in folder /etc/fstab
sed -i 's/\/swap.img/#&/' /etc/fstab

# sysctl params required by setup, params persist across reboots
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

# Apply sysctl params without reboot
sysctl --system

# verify that net.ipv4.ip_forward is set to 1
sysctl net.ipv4.ip_forward

# containerd binaries
wget https://github.com/containerd/containerd/releases/download/v1.7.13/containerd-1.7.13-linux-amd64.tar.gz
tar Cxzvf /usr/local containerd-1.7.13-linux-amd64.tar.gz

# systemd
mkdir -p /usr/local/lib/systemd/system
bash -c 'curl https://raw.githubusercontent.com/containerd/containerd/main/containerd.service > /usr/local/lib/systemd/system/containerd.service'
systemctl daemon-reload
systemctl enable --now containerd

# runc
wget https://github.com/opencontainers/runc/releases/download/v1.1.12/runc.amd64
install -m 755 runc.amd64 /usr/local/sbin/runc

# install cni plugins
wget https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.4.0.tgz

# create config file
mkdir /etc/containerd
bash -c 'containerd config default > /etc/containerd/config.toml'

# configure config file to use systemd cgroup driver
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# restart containerd service
systemctl restart containerd

# Download repository
DOWNLOAD_DIR="/usr/local/bin"
mkdir -p "$DOWNLOAD_DIR"

# install crictl
CRICTL_VERSION="v1.28.0"
ARCH="amd64"
wget "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz" | tar -C $DOWNLOAD_DIR -xz


# install kubelet, and kubeadm
RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"
ARCH="amd64"
cd $DOWNLOAD_DIR
wget https://dl.k8s.io/release/${RELEASE}/bin/linux/${ARCH}/{kubeadm,kubelet}
chmod +x {kubeadm,kubelet}

RELEASE_VERSION="v0.16.2"
curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubelet/kubelet.service" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | tee /usr/lib/systemd/system/kubelet.service
mkdir -p /usr/lib/systemd/system/kubelet.service.d
curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | tee /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf

systemctl enable --now kubelet

# install kubectl
wget "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
wget "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# install missing dependencies
apt-get install socat
apt-get install conntrack