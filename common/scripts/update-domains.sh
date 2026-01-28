#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$ROOT_DIR"

source "$ROOT_DIR/common/utils.sh" 2>/dev/null || {
  log_error() { echo "[ERROR] $*" >&2; }
  log_info() { echo "[INFO] $*"; }
  log_success() { echo "[OK] $*"; }
  log_warn() { echo "[WARN] $*" >&2; }
}

ACTION="${1:-check}"
DOMAIN="${2:-}"

check_updates() {
  local domain=$1
  local compose_file="$ROOT_DIR/generated/$domain/compose.yml"

  if [[ ! -f "$compose_file" ]]; then
    log_warn "Compose file not found for $domain (run 'make render DOMAIN=$domain' first), skipping"
    return 1
  fi

  log_info "Checking for updates: $domain"
  cd "$ROOT_DIR"

  local pull_output
  pull_output=$(docker compose -f "$compose_file" pull --dry-run 2>&1)
  local pull_status=$?

  if [[ $pull_status -ne 0 ]]; then
    if echo "$pull_output" | grep -qE "unauthorized|access.*denied|rate limit|pull.*access"; then
      log_warn "Update check failed for $domain (auth/rate limit issue)"
      return 1
    else
      log_warn "Update check failed for $domain: $pull_output"
      return 1
    fi
  fi

  if echo "$pull_output" | grep -qiE "would pull|pulling|up to date|already up to date"; then
    if echo "$pull_output" | grep -qiE "already up to date|up to date"; then
      log_success "$domain: All images are up to date"
      return 0
    else
      log_info "$domain: Updates available"
      echo "$pull_output" | grep -E "would pull|pulling" || echo "$pull_output"
      return 2
    fi
  else
    # If output doesn't match expected patterns, assume no updates
    log_info "$domain: No updates detected (or unable to determine)"
    return 0
  fi
}

apply_updates() {
  local domain=$1
  local compose_file="$ROOT_DIR/generated/$domain/compose.yml"

  if [[ ! -f "$compose_file" ]]; then
    log_error "Compose file not found for $domain (run 'make render DOMAIN=$domain' first)"
    return 1
  fi

  log_info "Applying updates: $domain"
  cd "$ROOT_DIR"

  log_info "Pulling latest images for $domain..."
  local pull_output
  pull_output=$(docker compose -f "$compose_file" pull 2>&1)
  local pull_status=$?

  if [[ $pull_status -ne 0 ]]; then
    if echo "$pull_output" | grep -qE "unauthorized|access.*denied|rate limit|pull.*access"; then
      log_error "Image pull failed for $domain (auth/rate limit issue)"
      return 1
    else
      log_error "Image pull failed for $domain: $pull_output"
      return 1
    fi
  fi

  log_info "Restarting containers for $domain with updated images..."
  local up_output
  up_output=$(docker compose -f "$compose_file" up -d 2>&1)
  local up_status=$?

  if [[ $up_status -eq 0 ]]; then
    log_success "$domain: Updates applied successfully"
    return 0
  else
    log_error "$domain: Failed to restart containers: $up_output"
    return 1
  fi
}

check_all() {
  log_info "Checking for updates across all domains..."
  local updated_count=0
  local total_count=0
  local failed_count=0

  for domain_dir in "$ROOT_DIR/domains"/*/; do
    local domain_name=$(basename "$domain_dir")
    if [[ -f "$domain_dir/metadata.yml" ]] && [[ -f "$ROOT_DIR/generated/$domain_name/compose.yml" ]]; then
      total_count=$((total_count + 1))
      if check_updates "$domain_name"; then
        local check_result=$?
        if [[ $check_result -eq 2 ]]; then
          updated_count=$((updated_count + 1))
        fi
      else
        failed_count=$((failed_count + 1))
      fi
    fi
  done

  log_info "Update check complete: $updated_count domain(s) with updates, $failed_count failed, $total_count total"
  return 0
}

apply_all() {
  log_info "Applying updates across all domains..."
  local success_count=0
  local failed_count=0
  local total_count=0

  for domain_dir in "$ROOT_DIR/domains"/*/; do
    local domain_name=$(basename "$domain_dir")
    if [[ -f "$domain_dir/metadata.yml" ]] && [[ -f "$ROOT_DIR/generated/$domain_name/compose.yml" ]]; then
      total_count=$((total_count + 1))
      if apply_updates "$domain_name"; then
        success_count=$((success_count + 1))
      else
        failed_count=$((failed_count + 1))
      fi
    fi
  done

  log_info "Update application complete: $success_count succeeded, $failed_count failed, $total_count total"
  if [[ $failed_count -gt 0 ]]; then
    return 1
  fi
  return 0
}

case "$ACTION" in
  check)
    if [[ -n "$DOMAIN" ]]; then
      check_updates "$DOMAIN"
      exit $?
    else
      check_all
      exit $?
    fi
    ;;
  apply)
    if [[ -z "$DOMAIN" ]]; then
      log_error "DOMAIN required for apply action (e.g., $0 apply <domain>)"
      exit 1
    fi
    apply_updates "$DOMAIN"
    exit $?
    ;;
  apply-all)
    apply_all
    exit $?
    ;;
  *)
    log_error "Unknown action: $ACTION"
    echo "Usage: $0 {check|apply|apply-all} [domain]"
    echo "  check [domain]     - Check for updates (all domains if domain not specified)"
    echo "  apply <domain>     - Apply updates for a specific domain"
    echo "  apply-all          - Apply updates for all domains"
    exit 1
    ;;
esac
