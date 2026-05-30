#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-}"
LETSENCRYPT_EMAIL_ARG="${2:-}"
DOMAIN_ARG="${3:-}"
EXTRA_DOMAINS=()
if (( $# > 3 )); then
  EXTRA_DOMAINS=("${@:4}")
fi
FORCE_RENEWAL="${FORCE_RENEWAL:-0}"

if [[ -z "${ENV_FILE}" ]]; then
  echo "Usage: $0 <servers/*.env> <email> [domain] [additional-domain ...]"
  echo "Example: $0 infra/servers/prod.env admin@example.com powershiftreport.com www.powershiftreport.com"
  echo "Set FORCE_RENEWAL=1 to force re-issuing a certificate before it is due."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ ! -f "${ENV_FILE}" ]]; then
  if [[ -f "${INFRA_DIR}/${ENV_FILE}" ]]; then
    ENV_FILE="${INFRA_DIR}/${ENV_FILE}"
  else
    echo "Env file not found: ${ENV_FILE}"
    exit 1
  fi
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL_ARG:-${LETSENCRYPT_EMAIL:-}}"
DOMAIN="${DOMAIN_ARG:-${DOMAIN:-powershiftreport.com}}"

if [[ -z "${LETSENCRYPT_EMAIL}" ]]; then
  echo "Email is required. Pass as arg #2 or LETSENCRYPT_EMAIL env."
  exit 1
fi

: "${SERVER_HOST:?missing}"
: "${SERVER_SSH_PORT:?missing}"
: "${SERVER_USER:?missing}"
: "${SERVER_APP_DIR:?missing}"
: "${IMAGE_REGISTRY:?missing}"
: "${IMAGE_NAME:?missing}"
: "${IMAGE_TAG:?missing}"

SSH_BASE=(ssh -p "${SERVER_SSH_PORT}" -o StrictHostKeyChecking=accept-new "${SERVER_USER}@${SERVER_HOST}")
CERT_DOMAINS=("${DOMAIN}" "${EXTRA_DOMAINS[@]}")
DOMAIN_ARGS=()
for cert_domain in "${CERT_DOMAINS[@]}"; do
  [[ -n "${cert_domain}" ]] && DOMAIN_ARGS+=("-d" "${cert_domain}")
done

if [[ "${#DOMAIN_ARGS[@]}" -eq 0 ]]; then
  echo "At least one domain is required."
  exit 1
fi

echo "Issuing/renewing Let's Encrypt cert for ${CERT_DOMAINS[*]} on ${SERVER_HOST} ..."

REMOTE_ARGS=(
  "${SERVER_APP_DIR}"
  "${SERVER_USER}"
  "${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
  "${NGINX_IMAGE:-nginx:1.27-alpine}"
  "${LETSENCRYPT_EMAIL}"
  "${FORCE_RENEWAL}"
  "${DOMAIN}"
  --
  "${DOMAIN_ARGS[@]}"
)

"${SSH_BASE[@]}" "bash -s --" "${REMOTE_ARGS[@]}" <<'REMOTE_SCRIPT'
set -euo pipefail

SERVER_APP_DIR="$1"
SERVER_USER="$2"
APP_IMAGE="$3"
NGINX_IMAGE="$4"
LETSENCRYPT_EMAIL="$5"
FORCE_RENEWAL="$6"
CERT_NAME="$7"
shift 7
shift
DOMAIN_ARGS=("$@")

DOCKER_CMD="docker"
if ! docker info >/dev/null 2>&1; then
  DOCKER_CMD="sudo docker"
fi

restart_stack() {
  cd "${SERVER_APP_DIR}/app"
  "${DOCKER_CMD}" compose --env-file "${SERVER_APP_DIR}/shared/compose.env" up -d --remove-orphans
}
trap restart_stack EXIT

sudo apt-get update -y
sudo apt-get install -y certbot

if [ -f "${SERVER_APP_DIR}/releases/current_image" ]; then
  APP_IMAGE="$(cat "${SERVER_APP_DIR}/releases/current_image")"
fi
export APP_IMAGE
export NGINX_IMAGE

test -f "${SERVER_APP_DIR}/app/docker-compose.yml"
test -f "${SERVER_APP_DIR}/shared/compose.env"

echo "Checking port 80 before standalone challenge ..."
cd "${SERVER_APP_DIR}/app"
"${DOCKER_CMD}" compose --env-file "${SERVER_APP_DIR}/shared/compose.env" down || true
if sudo ss -ltnp | grep -qE ':(80)\s'; then
  echo "Port 80 is still in use. Certbot standalone needs port 80."
  sudo ss -ltnp | grep -E ':(80)\s' || true
  exit 1
fi

CERTBOT_RENEW_ARGS=(--keep-until-expiring --expand)
if [ "${FORCE_RENEWAL}" = "1" ]; then
  CERTBOT_RENEW_ARGS=(--force-renewal --expand)
fi

sudo certbot certonly \
  --standalone \
  --non-interactive \
  --agree-tos \
  --email "${LETSENCRYPT_EMAIL}" \
  --cert-name "${CERT_NAME}" \
  "${CERTBOT_RENEW_ARGS[@]}" \
  "${DOMAIN_ARGS[@]}"

sudo mkdir -p "${SERVER_APP_DIR}/shared/ssl"
sudo cp "/etc/letsencrypt/live/${CERT_NAME}/fullchain.pem" "${SERVER_APP_DIR}/shared/ssl/fullchain.pem"
sudo cp "/etc/letsencrypt/live/${CERT_NAME}/privkey.pem" "${SERVER_APP_DIR}/shared/ssl/privkey.pem"
sudo chmod 600 "${SERVER_APP_DIR}/shared/ssl/privkey.pem"
sudo chmod 644 "${SERVER_APP_DIR}/shared/ssl/fullchain.pem"
sudo chown -R "${SERVER_USER}:${SERVER_USER}" "${SERVER_APP_DIR}/shared/ssl"

echo "Installed certificate:"
sudo openssl x509 -in "${SERVER_APP_DIR}/shared/ssl/fullchain.pem" -noout -subject -issuer -dates
REMOTE_SCRIPT

echo "Let's Encrypt setup completed for ${CERT_DOMAINS[*]}."
