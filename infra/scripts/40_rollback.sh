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

SSH_BASE=(ssh -p "${SERVER_SSH_PORT}" -o StrictHostKeyChecking=accept-new "${SERVER_USER}@${SERVER_HOST}")
NGINX_IMAGE="${NGINX_IMAGE:-nginx:1.27-alpine}"

echo "Rolling back deployment on ${SERVER_HOST} ..."

"${SSH_BASE[@]}" "set -e; \
  test -f ${SERVER_APP_DIR}/releases/previous_image; \
  ROLLBACK_IMAGE=\$(cat ${SERVER_APP_DIR}/releases/previous_image); \
  cd ${SERVER_APP_DIR}/app; \
  test -f ${SERVER_APP_DIR}/shared/compose.env; \
  test -f ${SERVER_APP_DIR}/shared/wp-config-sample.php; \
  DOCKER_CMD='docker'; \
  if ! docker info >/dev/null 2>&1; then DOCKER_CMD='sudo docker'; fi; \
  CODE_VOLUME=\$(grep -E '^WORDPRESS_DATA_VOLUME=' ${SERVER_APP_DIR}/shared/compose.env | head -n1 | cut -d'=' -f2-); \
  if [ -z \"\${CODE_VOLUME}\" ]; then CODE_VOLUME='wordpress_code_data'; fi; \
  export APP_IMAGE=\"\${ROLLBACK_IMAGE}\"; \
  export NGINX_IMAGE='${NGINX_IMAGE}'; \
  export APP_HTTP_PORT='${APP_HTTP_PORT:-80}'; \
  \${DOCKER_CMD} pull \"\${ROLLBACK_IMAGE}\" || true; \
  \${DOCKER_CMD} pull '${NGINX_IMAGE}' || true; \
  \${DOCKER_CMD} compose --env-file ${SERVER_APP_DIR}/shared/compose.env down || true; \
  \${DOCKER_CMD} volume rm \"\${CODE_VOLUME}\" >/dev/null 2>&1 || true; \
  \${DOCKER_CMD} compose --env-file ${SERVER_APP_DIR}/shared/compose.env up -d --remove-orphans; \
  \${DOCKER_CMD} exec wordpress_app sh -lc 'mkdir -p /var/www/html/wp-content/uploads && chown -R www-data:www-data /var/www/html/wp-content/uploads && chmod -R u+rwX,g+rwX /var/www/html/wp-content/uploads'; \
  \${DOCKER_CMD} exec wordpress_app sh -lc 'if [ -f /var/www/html/wp-config-sample.php ]; then cp -f /var/www/html/wp-config-sample.php /var/www/html/wp-config.php; elif [ ! -f /var/www/html/wp-config.php ]; then echo wp-config-sample.php not found; exit 1; fi; chown www-data:www-data /var/www/html/wp-config.php'; \
  echo \"\${ROLLBACK_IMAGE}\" > ${SERVER_APP_DIR}/releases/current_image"

echo "Rollback completed."
