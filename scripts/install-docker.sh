#!/usr/bin/env bash
# Run with sudo on the dedicated Ubuntu 24.04 lab VM only.
set -euo pipefail
[[ $EUID -eq 0 && $(hostname) == devops-vm ]] || { echo 'Run as root on devops-vm only' >&2; exit 1; }
apt-get update
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]] || { echo 'Expected Ubuntu 24.04' >&2; exit 1; }
cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $VERSION_CODENAME
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker devops
systemctl enable --now docker
docker version
docker compose version
docker run --rm hello-world
