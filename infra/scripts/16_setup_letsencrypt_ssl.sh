#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-}"
LETSENCRYPT_EMAIL="${2:-${LETSENCRYPT_EMAIL:-}}"
DOMAIN="${3:-${DOMAIN:-powershiftreport.com}}"

if [[ -z "${ENV_FILE}" ]]; then
  echo "Usage: $0 <servers/*.env> <email> [domain]"
  exit 1
fi

if [[ -z "${LETSENCRYPT_EMAIL}" ]]; then
  echo "Email is required. Pass as arg #2 or LETSENCRYPT_EMAIL env."
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

: "${SERVER_HOST:?missing}"
: "${SERVER_SSH_PORT:?missing}"
: "${SERVER_USER:?missing}"
: "${SERVER_APP_DIR:?missing}"
: "${IMAGE_REGISTRY:?missing}"
: "${IMAGE_NAME:?missing}"
: "${IMAGE_TAG:?missing}"

SSH_BASE=(ssh -p "${SERVER_SSH_PORT}" -o StrictHostKeyChecking=accept-new "${SERVER_USER}@${SERVER_HOST}")

echo "Issuing Let's Encrypt cert for ${DOMAIN} on ${SERVER_HOST} ..."

"${SSH_BASE[@]}" "set -e; \
  sudo apt-get update -y; \
  sudo apt-get install -y certbot; \
  DOCKER_CMD='docker'; \
  if ! docker info >/dev/null 2>&1; then DOCKER_CMD='sudo docker'; fi; \
  APP_IMAGE='${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}'; \
  NGINX_IMAGE='${NGINX_IMAGE:-nginx:1.27-alpine}'; \
  if [ -f ${SERVER_APP_DIR}/releases/current_image ]; then APP_IMAGE=\$(cat ${SERVER_APP_DIR}/releases/current_image); fi; \
  export APP_IMAGE; \
  export NGINX_IMAGE; \
  cd ${SERVER_APP_DIR}/app; \
  \${DOCKER_CMD} compose --env-file ${SERVER_APP_DIR}/shared/compose.env down || true; \
  sudo certbot certonly --standalone --non-interactive --agree-tos --email '${LETSENCRYPT_EMAIL}' -d '${DOMAIN}'; \
  sudo mkdir -p ${SERVER_APP_DIR}/shared/ssl; \
  sudo cp /etc/letsencrypt/live/${DOMAIN}/fullchain.pem ${SERVER_APP_DIR}/shared/ssl/fullchain.pem; \
  sudo cp /etc/letsencrypt/live/${DOMAIN}/privkey.pem ${SERVER_APP_DIR}/shared/ssl/privkey.pem; \
  sudo chmod 600 ${SERVER_APP_DIR}/shared/ssl/privkey.pem; \
  sudo chmod 644 ${SERVER_APP_DIR}/shared/ssl/fullchain.pem; \
  sudo chown -R ${SERVER_USER}:${SERVER_USER} ${SERVER_APP_DIR}/shared/ssl; \
  \${DOCKER_CMD} compose --env-file ${SERVER_APP_DIR}/shared/compose.env up -d --remove-orphans"

echo "Let's Encrypt setup completed for ${DOMAIN}."
