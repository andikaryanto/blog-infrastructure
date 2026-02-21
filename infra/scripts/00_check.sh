#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-}"
if [[ -z "${ENV_FILE}" ]]; then
  echo "Usage: $0 <servers/*.env>"
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Env file not found: ${ENV_FILE}"
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

required_vars=(
  SERVER_HOST
  SERVER_SSH_PORT
  SERVER_USER
  SERVER_APP_DIR
  IMAGE_REGISTRY
  IMAGE_NAME
  IMAGE_TAG
)

for v in "${required_vars[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "Missing required variable: ${v}"
    exit 1
  fi
done

required_cmds=(bash ssh)
for c in "${required_cmds[@]}"; do
  if ! command -v "${c}" >/dev/null 2>&1; then
    echo "Missing local command: ${c}"
    exit 1
  fi
done

if command -v rsync >/dev/null 2>&1; then
  echo "Transfer method: rsync"
elif command -v scp >/dev/null 2>&1; then
  echo "Transfer method: scp (rsync not found)"
else
  echo "Missing local command: rsync or scp"
  exit 1
fi

if [[ -n "${SERVER_HOSTKEY_SHA256:-}" ]]; then
  if ! command -v ssh-keyscan >/dev/null 2>&1 || ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "Missing local command: ssh-keyscan and/or ssh-keygen (required for fingerprint check)"
    exit 1
  fi
  SCANNED_FINGERPRINT="$(
    ssh-keyscan -p "${SERVER_SSH_PORT}" "${SERVER_HOST}" 2>/dev/null \
      | ssh-keygen -lf - -E sha256 \
      | awk '{print $2}' \
      | head -n 1
  )"
  if [[ -z "${SCANNED_FINGERPRINT}" ]]; then
    echo "Failed to scan host key fingerprint from ${SERVER_HOST}:${SERVER_SSH_PORT}"
    exit 1
  fi
  if [[ "${SCANNED_FINGERPRINT}" != "${SERVER_HOSTKEY_SHA256}" ]]; then
    echo "Host key fingerprint mismatch!"
    echo "Expected: ${SERVER_HOSTKEY_SHA256}"
    echo "Actual:   ${SCANNED_FINGERPRINT}"
    exit 1
  fi
  echo "Host key fingerprint verified: ${SCANNED_FINGERPRINT}"
else
  echo "Warning: SERVER_HOSTKEY_SHA256 is not set; host key fingerprint is not verified."
fi

echo "Checking SSH connectivity to ${SERVER_USER}@${SERVER_HOST}:${SERVER_SSH_PORT} ..."
ssh -p "${SERVER_SSH_PORT}" -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
  "${SERVER_USER}@${SERVER_HOST}" "echo SSH_OK" >/dev/null

echo "Check completed successfully."
