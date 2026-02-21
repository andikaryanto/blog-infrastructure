#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-}"
if [[ -z "${ENV_FILE}" ]]; then
  echo "Usage: $0 <servers/*.env>"
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

: "${SERVER_HOST:?missing}"
: "${SERVER_SSH_PORT:?missing}"
: "${SERVER_USER:?missing}"
: "${SERVER_APP_DIR:?missing}"

ENV_NAME="${ENV_NAME:-prod}"
APP_ENV_TEMPLATE="${APP_ENV_TEMPLATE:-app/env/app.env.${ENV_NAME}.template}"
COMPOSE_ENV_TEMPLATE="${COMPOSE_ENV_TEMPLATE:-app/env/compose.env.${ENV_NAME}.template}"
WP_CONFIG_SAMPLE_TEMPLATE="${WP_CONFIG_SAMPLE_TEMPLATE:-app/env/wp-config-sample.php.${ENV_NAME}.template}"
APP_ENV_TEMPLATE_PATH="${APP_ENV_TEMPLATE}"
COMPOSE_ENV_TEMPLATE_PATH="${COMPOSE_ENV_TEMPLATE}"
WP_CONFIG_SAMPLE_TEMPLATE_PATH="${WP_CONFIG_SAMPLE_TEMPLATE}"

if [[ ! -f "${APP_ENV_TEMPLATE_PATH}" ]]; then
  APP_ENV_TEMPLATE_PATH="${INFRA_DIR}/${APP_ENV_TEMPLATE}"
fi
if [[ ! -f "${COMPOSE_ENV_TEMPLATE_PATH}" ]]; then
  COMPOSE_ENV_TEMPLATE_PATH="${INFRA_DIR}/${COMPOSE_ENV_TEMPLATE}"
fi
if [[ ! -f "${WP_CONFIG_SAMPLE_TEMPLATE_PATH}" ]]; then
  WP_CONFIG_SAMPLE_TEMPLATE_PATH="${INFRA_DIR}/${WP_CONFIG_SAMPLE_TEMPLATE}"
fi
if [[ ! -f "${APP_ENV_TEMPLATE_PATH}" ]]; then
  echo "Template ${APP_ENV_TEMPLATE} not found, fallback to app/env/app.env.template"
  APP_ENV_TEMPLATE_PATH="${INFRA_DIR}/app/env/app.env.template"
fi
if [[ ! -f "${COMPOSE_ENV_TEMPLATE_PATH}" ]]; then
  echo "Template ${COMPOSE_ENV_TEMPLATE} not found, fallback to app/env/compose.env.template"
  COMPOSE_ENV_TEMPLATE_PATH="${INFRA_DIR}/app/env/compose.env.template"
fi
if [[ ! -f "${WP_CONFIG_SAMPLE_TEMPLATE_PATH}" ]]; then
  echo "Template ${WP_CONFIG_SAMPLE_TEMPLATE} not found, fallback to app/env/wp-config-sample.php.template"
  WP_CONFIG_SAMPLE_TEMPLATE_PATH="${INFRA_DIR}/app/env/wp-config-sample.php.template"
fi

SSH_BASE=(ssh -p "${SERVER_SSH_PORT}" -o StrictHostKeyChecking=accept-new "${SERVER_USER}@${SERVER_HOST}")
RSYNC_SSH=("ssh" "-p" "${SERVER_SSH_PORT}" "-o" "StrictHostKeyChecking=accept-new")

copy_to_server() {
  local src="$1"
  local dst="$2"
  if command -v rsync >/dev/null 2>&1; then
    rsync -avz -e "${RSYNC_SSH[*]}" "${src}" "${SERVER_USER}@${SERVER_HOST}:${dst}"
  else
    scp -P "${SERVER_SSH_PORT}" -o StrictHostKeyChecking=accept-new "${src}" "${SERVER_USER}@${SERVER_HOST}:${dst}"
  fi
}

echo "Provisioning app configs to ${SERVER_HOST} ..."

"${SSH_BASE[@]}" "set -e; \
  if mkdir -p ${SERVER_APP_DIR}/app/nginx ${SERVER_APP_DIR}/shared ${SERVER_APP_DIR}/releases ${SERVER_APP_DIR}/shared/ssl 2>/dev/null; then \
    true; \
  else \
    sudo mkdir -p ${SERVER_APP_DIR}/app/nginx ${SERVER_APP_DIR}/shared ${SERVER_APP_DIR}/releases ${SERVER_APP_DIR}/shared/ssl; \
  fi; \
  sudo chown -R ${SERVER_USER}:${SERVER_USER} ${SERVER_APP_DIR}"

copy_to_server "${INFRA_DIR}/app/docker-compose.yml" "${SERVER_APP_DIR}/app/docker-compose.yml"
copy_to_server "${INFRA_DIR}/app/nginx/default.conf" "${SERVER_APP_DIR}/app/nginx/default.conf"
copy_to_server "${APP_ENV_TEMPLATE_PATH}" "${SERVER_APP_DIR}/app.env.template"
copy_to_server "${COMPOSE_ENV_TEMPLATE_PATH}" "${SERVER_APP_DIR}/compose.env.template"
copy_to_server "${WP_CONFIG_SAMPLE_TEMPLATE_PATH}" "${SERVER_APP_DIR}/wp-config-sample.php.template"

"${SSH_BASE[@]}" "test -f ${SERVER_APP_DIR}/shared/app.env || cp ${SERVER_APP_DIR}/app.env.template ${SERVER_APP_DIR}/shared/app.env 2>/dev/null || true"
"${SSH_BASE[@]}" "test -f ${SERVER_APP_DIR}/shared/compose.env || cp ${SERVER_APP_DIR}/compose.env.template ${SERVER_APP_DIR}/shared/compose.env 2>/dev/null || true"
"${SSH_BASE[@]}" "cp -f ${SERVER_APP_DIR}/wp-config-sample.php.template ${SERVER_APP_DIR}/shared/wp-config-sample.php 2>/dev/null || true"

echo "Provision completed."
