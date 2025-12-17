#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$ROOT_DIR"

source "$ROOT_DIR/common/utils.sh" 2>/dev/null || {
  log_error() { echo "[ERROR] $*" >&2; }
  log_info() { echo "[INFO] $*"; }
  log_success() { echo "[OK] $*"; }
  log_warn() { echo "[WARN] $*" >&2; }
}

LOG_FILE="${LOG_FILE:-/var/log/pi-forge-updates.log}"
EMAIL_TO="${ALERT_EMAIL:-}"

if [[ ! -f "$ROOT_DIR/.env" ]]; then
  log_error ".env file not found"
  exit 1
fi

if [[ -f "$ROOT_DIR/config-registry/env/base.env" ]]; then
  set -a
  source "$ROOT_DIR/config-registry/env/base.env" 2>/dev/null || true
  set +a
fi

set -a
source "$ROOT_DIR/.env" 2>/dev/null || true
set +a

extract_version() {
  local image_tag=$1
  echo "$image_tag" | sed -E 's/.*:([0-9]+\.[0-9]+).*/\1/' | head -1
}

check_image_update() {
  local image=$1
  local current_tag=$2
  local current_version=$(extract_version "$current_tag")

  if [[ -z "$current_version" ]]; then
    return 0
  fi

  local repo=$(echo "$image" | cut -d: -f1)
  local latest_tag=$(docker run --rm quay.io/skopeo/skopeo:latest list-tags "docker://$repo" 2>/dev/null | \
    python3 -c "import sys, json; \
      data = json.load(sys.stdin); \
      tags = [t for t in data.get('Tags', []) if t.replace('.', '').isdigit() or ':' in t]; \
      versions = [t for t in tags if '.' in t]; \
      major_minor = {}; \
      for v in versions: \
        parts = v.split('.'); \
        if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit(): \
          key = f\"{parts[0]}.{parts[1]}\"; \
          if key not in major_minor or v > major_minor[key]: \
            major_minor[key] = v; \
      if major_minor: \
        latest = max(major_minor.values()); \
        print(latest)" 2>/dev/null || echo "")

  if [[ -n "$latest_tag" && "$latest_tag" != "$current_tag" ]]; then
    local latest_version=$(extract_version "$latest_tag")
    if [[ "$latest_version" != "$current_version" ]]; then
      echo "$image:$current_tag -> $image:$latest_tag"
    fi
  fi
}

log_message() {
  local msg="$1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" | tee -a "$LOG_FILE"
}

send_email() {
  local subject="$1"
  local body="$2"

  if [[ -z "$EMAIL_TO" ]] || [[ -z "$SMTP_ADDRESS" ]]; then
    return 0
  fi

  if ! command -v sendmail >/dev/null 2>&1; then
    log_warn "sendmail not available, skipping email notification"
    return 0
  fi

  {
    echo "To: $EMAIL_TO"
    echo "From: ${SMTP_FROM:-noreply@${DOMAIN:-localhost}}"
    echo "Subject: $subject"
    echo ""
    echo "$body"
  } | sendmail -t 2>/dev/null || log_warn "Failed to send email"
}

log_message "Starting LTS update check..."

UPDATES=()
IMAGES=()

IMAGES=()
set +u
[ -n "${FORGEJO_IMAGE:-}" ] && IMAGES+=("code.forgejo.org/forgejo/forgejo:${FORGEJO_IMAGE##*:}")
[ -n "${FORGEJO_ACTIONS_RUNNER_IMAGE:-}" ] && IMAGES+=("code.forgejo.org/forgejo/runner:${FORGEJO_ACTIONS_RUNNER_IMAGE##*:}")
[ -n "${POSTGRES_IMAGE:-}" ] && IMAGES+=("postgres:${POSTGRES_IMAGE##*:}")
[ -n "${PROMETHEUS_IMAGE:-}" ] && IMAGES+=("prom/prometheus:${PROMETHEUS_IMAGE##*:}")
[ -n "${ALERTMANAGER_IMAGE:-}" ] && IMAGES+=("prom/alertmanager:${ALERTMANAGER_IMAGE##*:}")
[ -n "${GRAFANA_IMAGE:-}" ] && IMAGES+=("grafana/grafana:${GRAFANA_IMAGE##*:}")
[ -n "${LOKI_IMAGE:-}" ] && IMAGES+=("grafana/loki:${LOKI_IMAGE##*:}")
[ -n "${ALLOY_IMAGE:-}" ] && IMAGES+=("grafana/alloy:${ALLOY_IMAGE##*:}")
[ -n "${PIHOLE_IMAGE:-}" ] && IMAGES+=("pihole/pihole:${PIHOLE_IMAGE##*:}")
[ -n "${UNBOUND_IMAGE:-}" ] && IMAGES+=("crazymax/unbound:${UNBOUND_IMAGE##*:}")
[ -n "${WOODPECKER_SERVER_IMAGE:-}" ] && IMAGES+=("woodpeckerci/woodpecker-server:${WOODPECKER_SERVER_IMAGE##*:}")
[ -n "${WOODPECKER_RUNNER_IMAGE:-}" ] && IMAGES+=("woodpeckerci/woodpecker-agent:${WOODPECKER_RUNNER_IMAGE##*:}")
set -u

for image_tag in "${IMAGES[@]}"; do
  if [[ -z "$image_tag" ]] || [[ "$image_tag" == *":*" ]]; then
    continue
  fi

  update=$(check_image_update "$image_tag")
  if [[ -n "$update" ]]; then
    UPDATES+=("$update")
    log_message "Update available: $update"
  fi
done

if [[ ${#UPDATES[@]} -eq 0 ]]; then
  log_message "No LTS updates available"
  exit 0
fi

log_message "Found ${#UPDATES[@]} LTS update(s) available"

BODY="Pi Forge LTS Update Check Results

The following LTS updates are available:

$(printf '%s\n' "${UPDATES[@]}")

To apply updates, run:
  make deploy DOMAIN=<domain>

Or update all domains:
  make deploy-all

This is an automated check. Updates are not applied automatically.
"

send_email "Pi Forge: LTS Updates Available" "$BODY"

log_message "Update check complete"

