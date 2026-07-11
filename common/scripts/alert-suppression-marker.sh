#!/usr/bin/env bash
# Toggle the alert-suppression marker for runner/CI domains, which are
# expected to sit idle between jobs and would otherwise page on ContainerDown.
set -euo pipefail

ACTION="${1:?Usage: $0 [enable|disable] domain}"
DOMAIN="${2:?Usage: $0 [enable|disable] domain}"
MARKER_DIR="/srv/monitoring/alert-suppression"
MARKER_FILE="${MARKER_DIR}/${DOMAIN}.down"

if ! echo "${DOMAIN}" | grep -qE "(runner|actions-runner|woodpecker)"; then
  exit 0
fi

case "${ACTION}" in
  enable)
    mkdir -p "${MARKER_DIR}"
    touch "${MARKER_FILE}"
    echo "[AlertSuppression] Enabled for ${DOMAIN}"
    ;;
  disable)
    rm -f "${MARKER_FILE}" 2>/dev/null || true
    echo "[AlertSuppression] Disabled for ${DOMAIN}"
    ;;
  *)
    echo "Usage: $0 [enable|disable] domain" >&2
    exit 1
    ;;
esac
