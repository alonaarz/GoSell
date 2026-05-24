#!/bin/bash
set -euo pipefail

# Конфігурація під твої дані
AGENT_USER="agent001"
AGENT_HOME="/home/agent001"
AGENT_WORKDIR="/home/agent001/workspace"

# Install Java
sudo apt update
sudo apt install openjdk-21-jre openjdk-21-jdk -y

# Install Docker
sudo apt install ca-certificates curl -y
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "$${UBUNTU_CODENAME:-$$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# Створюємо користувача agent001 (якщо його ще немає)
sudo useradd -m -d "${AGENT_HOME}" -s /bin/bash "${AGENT_USER}" || true
# Додаємо його в групу docker, щоб Jenkins міг збирати твої образи без sudo
sudo usermod -aG docker "${AGENT_USER}"

# Створюємо робочу директорію для білдів
sudo mkdir -p "${AGENT_WORKDIR}"
sudo chown -R "${AGENT_USER}:${AGENT_USER}" "${AGENT_HOME}"

# Налаштовуємо SSH ключі в домашній папці agent001, щоб Майстер міг підключитися
sudo mkdir -p "${AGENT_HOME}/.ssh"
sudo tee "${AGENT_HOME}/.ssh/authorized_keys" > /dev/null <<'KEYEOF'
${public_key}
KEYEOF

# Виставляємо правильні права доступу для SSH (інакше Linux заблокує вхід)
sudo chmod 700 "${AGENT_HOME}/.ssh"
sudo chmod 600 "${AGENT_HOME}/.ssh/authorized_keys"
sudo chown -R "${AGENT_USER}:${AGENT_USER}" "${AGENT_HOME}/.ssh"

echo "--- Jenkins Agent installation complete ---"
echo "SSH authorized_keys configured for user: ${AGENT_USER}"
echo "Agent workdir: ${AGENT_WORKDIR}"
echo "Waiting for master to connect via SSH..."