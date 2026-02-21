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
: "${IMAGE_REGISTRY:?missing}"
: "${IMAGE_NAME:?missing}"
: "${IMAGE_TAG:?missing}"

APP_IMAGE="${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
NGINX_IMAGE="${NGINX_IMAGE:-nginx:1.27-alpine}"
SSH_BASE=(ssh -p "${SERVER_SSH_PORT}" -o StrictHostKeyChecking=accept-new "${SERVER_USER}@${SERVER_HOST}")

echo "Deploying ${APP_IMAGE} to ${SERVER_HOST} ..."

"${SSH_BASE[@]}" "set -e; \
  cd ${SERVER_APP_DIR}/app; \
  mkdir -p ${SERVER_APP_DIR}/releases; \
  test -f ${SERVER_APP_DIR}/shared/app.env; \
  test -f ${SERVER_APP_DIR}/shared/compose.env; \
  test -f ${SERVER_APP_DIR}/shared/wp-config-sample.php; \
  grep -Eq '^MARIADB_DATABASE=.+' ${SERVER_APP_DIR}/shared/compose.env; \
  grep -Eq '^MARIADB_USER=.+' ${SERVER_APP_DIR}/shared/compose.env; \
  grep -Eq '^MARIADB_PASSWORD=.+' ${SERVER_APP_DIR}/shared/compose.env; \
  grep -Eq '^MARIADB_ROOT_PASSWORD=.+' ${SERVER_APP_DIR}/shared/compose.env; \
  DOCKER_CMD='docker'; \
  if ! docker info >/dev/null 2>&1; then DOCKER_CMD='sudo docker'; fi; \
  if [ -f ${SERVER_APP_DIR}/releases/current_image ]; then cp ${SERVER_APP_DIR}/releases/current_image ${SERVER_APP_DIR}/releases/previous_image; fi; \
  CODE_VOLUME=\$(grep -E '^WORDPRESS_DATA_VOLUME=' ${SERVER_APP_DIR}/shared/compose.env | head -n1 | cut -d'=' -f2-); \
  if [ -z \"\${CODE_VOLUME}\" ]; then CODE_VOLUME='wordpress_code_data'; fi; \
  export APP_IMAGE='${APP_IMAGE}'; \
  export NGINX_IMAGE='${NGINX_IMAGE}'; \
  export APP_HTTP_PORT='${APP_HTTP_PORT:-80}'; \
  \${DOCKER_CMD} pull '${APP_IMAGE}'; \
  \${DOCKER_CMD} pull '${NGINX_IMAGE}'; \
  \${DOCKER_CMD} compose --env-file ${SERVER_APP_DIR}/shared/compose.env down || true; \
  \${DOCKER_CMD} volume rm \"\${CODE_VOLUME}\" >/dev/null 2>&1 || true; \
  \${DOCKER_CMD} compose --env-file ${SERVER_APP_DIR}/shared/compose.env up -d --remove-orphans; \
  \${DOCKER_CMD} exec wordpress_app sh -lc 'if [ -f /var/www/html/wp-config-sample.php ]; then cp -f /var/www/html/wp-config-sample.php /var/www/html/wp-config.php; elif [ ! -f /var/www/html/wp-config.php ]; then echo wp-config-sample.php not found; exit 1; fi; chown www-data:www-data /var/www/html/wp-config.php'; \
  echo '${APP_IMAGE}' > ${SERVER_APP_DIR}/releases/current_image"

echo "Deploy completed."
