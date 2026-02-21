#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-}"
if [[ -z "${ENV_FILE}" ]]; then
  echo "Usage: $0 <servers/*.env>"
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

: "${SERVER_HOST:?missing}"
: "${SERVER_SSH_PORT:?missing}"
: "${SERVER_USER:?missing}"
: "${SERVER_APP_DIR:?missing}"

DEPLOY_USER="${DEPLOY_USER:-deploy}"
SSH_PUB_KEY_PATH="${SSH_PUB_KEY_PATH:-}"

SSH_BASE=(ssh -p "${SERVER_SSH_PORT}" -o StrictHostKeyChecking=accept-new "${SERVER_USER}@${SERVER_HOST}")

echo "Bootstrapping server ${SERVER_HOST} ..."

"${SSH_BASE[@]}" "sudo apt-get update -y && sudo apt-get install -y ca-certificates curl gnupg lsb-release ufw"

"${SSH_BASE[@]}" "if ! command -v docker >/dev/null 2>&1; then \
  sudo install -m 0755 -d /etc/apt/keyrings && \
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
  sudo chmod a+r /etc/apt/keyrings/docker.gpg && \
  echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null && \
  sudo apt-get update -y && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; \
fi"

"${SSH_BASE[@]}" "id -u ${DEPLOY_USER} >/dev/null 2>&1 || sudo useradd -m -s /bin/bash ${DEPLOY_USER}"
"${SSH_BASE[@]}" "sudo usermod -aG docker ${DEPLOY_USER}"
"${SSH_BASE[@]}" "sudo usermod -aG docker ${SERVER_USER}"
"${SSH_BASE[@]}" "sudo mkdir -p ${SERVER_APP_DIR}/{app,shared,releases} && sudo chown -R ${SERVER_USER}:${SERVER_USER} ${SERVER_APP_DIR}"

if [[ -n "${SSH_PUB_KEY_PATH}" && -f "${SSH_PUB_KEY_PATH/#\~/$HOME}" ]]; then
  KEY_PATH_EXPANDED="${SSH_PUB_KEY_PATH/#\~/$HOME}"
  KEY_CONTENT="$(cat "${KEY_PATH_EXPANDED}")"
  "${SSH_BASE[@]}" "sudo -u ${DEPLOY_USER} mkdir -p /home/${DEPLOY_USER}/.ssh && sudo -u ${DEPLOY_USER} chmod 700 /home/${DEPLOY_USER}/.ssh"
  "${SSH_BASE[@]}" "grep -qxF '${KEY_CONTENT}' /home/${DEPLOY_USER}/.ssh/authorized_keys 2>/dev/null || echo '${KEY_CONTENT}' | sudo -u ${DEPLOY_USER} tee -a /home/${DEPLOY_USER}/.ssh/authorized_keys >/dev/null"
  "${SSH_BASE[@]}" "sudo -u ${DEPLOY_USER} chmod 600 /home/${DEPLOY_USER}/.ssh/authorized_keys"
fi

"${SSH_BASE[@]}" "sudo ufw --force reset; \
  sudo ufw default deny incoming; \
  sudo ufw default allow outgoing; \
  sudo ufw allow ${SERVER_SSH_PORT}/tcp; \
  sudo ufw allow 80/tcp; \
  sudo ufw allow 443/tcp; \
  sudo ufw --force enable"

echo "Bootstrap completed."
