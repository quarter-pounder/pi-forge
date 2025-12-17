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

ACTION="${1:-start}"

if [[ "$ACTION" != "start" && "$ACTION" != "stop" ]]; then
  echo "Usage: $0 [start|stop]"
  exit 1
fi

wait_for_docker() {
  local max_attempts=30
  local attempt=0
  while ! docker ps >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [[ $attempt -ge $max_attempts ]]; then
      log_error "Docker daemon not ready after $max_attempts attempts"
      return 1
    fi
    sleep 1
  done
  log_success "Docker daemon is ready"
}

get_container_state() {
  local container_name=$1
  docker inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null || echo "none"
}

is_container_healthy() {
  local container_name=$1
  local state=$(get_container_state "$container_name")

  if [[ "$state" != "running" ]]; then
    return 1
  fi

  local health=$(docker inspect --format '{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")

  if [[ "$health" == "healthy" ]]; then
    return 0
  elif [[ "$health" == "none" ]]; then
    return 0
  elif [[ "$health" == "starting" ]]; then
    return 1
  fi

  return 1
}

wait_for_domain_healthy() {
  local domain=$1
  local compose_file="$ROOT_DIR/generated/$domain/compose.yml"
  local max_attempts=90
  local attempt=0

  if [[ ! -f "$compose_file" ]]; then
    return 1
  fi

  while [[ $attempt -lt $max_attempts ]]; do
    local containers=$(docker compose -f "$compose_file" ps --format json 2>/dev/null | \
      python3 -c "import sys, json; \
        try: \
          data = [json.loads(l) for l in sys.stdin if l.strip()]; \
          containers = [c['Name'] for c in data if c.get('State') == 'running']; \
          print(' '.join(containers)) \
        except: pass" 2>/dev/null || echo "")

    if [[ -z "$containers" ]]; then
      attempt=$((attempt + 1))
      sleep 2
      continue
    fi

    local all_healthy=true
    local unhealthy_count=0
    for container in $containers; do
      if ! is_container_healthy "$container"; then
        all_healthy=false
        unhealthy_count=$((unhealthy_count + 1))
      fi
    done

    if [[ "$all_healthy" == "true" ]]; then
      log_success "Domain $domain is healthy"
      return 0
    fi

    if [[ $((attempt % 15)) -eq 0 ]] && [[ $attempt -gt 0 ]]; then
      log_info "Domain $domain: $unhealthy_count container(s) not yet healthy (attempt $attempt/$max_attempts)"
    fi

    attempt=$((attempt + 1))
    sleep 2
  done

  local running_count=$(echo "$containers" | wc -w)
  log_warn "Domain $domain not fully healthy after $max_attempts attempts ($running_count container(s) running)"
  return 1
}

should_start_domain() {
  local domain=$1
  local compose_file="$ROOT_DIR/generated/$domain/compose.yml"

  if [[ ! -f "$compose_file" ]]; then
    return 1
  fi

  local containers=$(docker compose -f "$compose_file" ps --format json 2>/dev/null | \
    python3 -c "import sys, json; \
      try: \
        data = [json.loads(l) for l in sys.stdin if l.strip()]; \
        for c in data: \
          state = c.get('State', ''); \
          if state == 'running': \
            print('running'); \
            break; \
          elif state == 'exited' or state == 'stopped': \
            print('stopped'); \
            break; \
      except: pass" 2>/dev/null || echo "none")

  if [[ "$containers" == "running" ]]; then
    return 0
  elif [[ "$containers" == "stopped" ]]; then
    return 1
  else
    return 0
  fi
}

deploy_domain() {
  local domain=$1
  local compose_file="$ROOT_DIR/generated/$domain/compose.yml"

  if [[ ! -f "$compose_file" ]]; then
    log_warn "Compose file not found for $domain (run 'make render DOMAIN=$domain' first), skipping"
    return 1
  fi

  log_info "Starting domain: $domain"
  cd "$ROOT_DIR"

  log_info "Starting containers for $domain using docker compose..."
  local compose_output
  compose_output=$(docker compose -f "$compose_file" up -d --pull always 2>&1)
  local compose_status=$?

  if [[ $compose_status -eq 0 ]]; then
    log_info "Domain $domain containers started"
    sleep 3
    local running_count=$(docker compose -f "$compose_file" ps --status running --format json 2>/dev/null | \
      python3 -c "import sys, json; \
        try: \
          data = [json.loads(l) for l in sys.stdin if l.strip()]; \
          print(len([c for c in data if c.get('State') == 'running'])) \
        except: print('0')" 2>/dev/null || echo "0")
    log_info "Domain $domain: $running_count container(s) running"
    return 0
  else
    log_error "Failed to start $domain"
    log_error "Docker compose error: ${compose_output:0:500}"
    return 1
  fi
}

stop_domain() {
  local domain=$1
  local compose_file="$ROOT_DIR/generated/$domain/compose.yml"

  if [[ ! -f "$compose_file" ]]; then
    return 0
  fi

  log_info "Stopping domain: $domain"
  cd "$ROOT_DIR"
  docker compose -f "$compose_file" down >/dev/null 2>&1 || true
}

declare -A CRITICAL_DEPS=(
  ["adblocker"]=""
  ["postgres"]=""
  ["monitoring"]=""
  ["tunnel"]=""
  ["forgejo"]="postgres"
  ["woodpecker"]="postgres forgejo"
  ["woodpecker-runner"]="woodpecker forgejo"
  ["forgejo-actions-runner"]="forgejo"
  ["registry"]="forgejo"
)

declare -A STARTED=()

start_domain_recursive() {
  local domain=$1
  local deps="${CRITICAL_DEPS[$domain]:-}"

  if [[ -n "${STARTED[$domain]:-}" ]]; then
    return 0
  fi

  if ! should_start_domain "$domain"; then
    log_info "Domain $domain was stopped, preserving state"
    return 0
  fi

  for dep in $deps; do
    if [[ -n "$dep" ]] && [[ -z "${STARTED[$dep]:-}" ]]; then
      start_domain_recursive "$dep"
      if ! wait_for_domain_healthy "$dep"; then
        log_error "Critical dependency $dep failed to become healthy, aborting $domain"
        return 1
      fi
    fi
  done

  if deploy_domain "$domain"; then
    STARTED[$domain]=1
    wait_for_domain_healthy "$domain" || {
      if [[ "$domain" == "adblocker" ]]; then
        log_warn "Adblocker failed to become healthy - DNS fallback will be used"
        log_info "System will continue with fallback DNS (1.1.1.1, 8.8.8.8)"
      elif [[ -n "$deps" ]]; then
        log_error "Critical domain $domain failed to become healthy"
        return 1
      else
        log_warn "Domain $domain started but not fully healthy (non-critical, continuing)"
      fi
    }
  else
    if [[ "$domain" == "adblocker" ]]; then
      log_warn "Adblocker failed to start - DNS fallback will be used"
      log_info "System will continue with fallback DNS (1.1.1.1, 8.8.8.8)"
      STARTED[$domain]=1
    elif [[ -n "$deps" ]]; then
      log_error "Failed to start $domain (has critical dependencies)"
      return 1
    else
      log_warn "Failed to start $domain (non-critical, continuing)"
    fi
  fi
}

if [[ "$ACTION" == "start" ]]; then
  log_info "Starting domain orchestration..."
  wait_for_docker

  found_domains=0
  skipped_domains=0
  # Start adblocker first (critical for DNS), then postgres, then others
  for domain in adblocker postgres monitoring tunnel forgejo registry woodpecker forgejo-actions-runner woodpecker-runner github-actions-runner; do
    if [[ -f "$ROOT_DIR/generated/$domain/compose.yml" ]]; then
      found_domains=$((found_domains + 1))
      start_domain_recursive "$domain"
    else
      skipped_domains=$((skipped_domains + 1))
      log_info "Domain $domain not rendered (compose.yml not found), skipping"
    fi
  done

  if [[ $found_domains -eq 0 ]]; then
    log_warn "No domains found to start. Render domains first with: make render DOMAIN=<name>"
  elif [[ $skipped_domains -gt 0 ]]; then
    log_info "Skipped $skipped_domains domain(s) (not rendered), started $found_domains domain(s)"
  fi

  log_success "Domain orchestration complete"
else
  log_info "Stopping all domains..."
  wait_for_docker

  for domain_dir in "$ROOT_DIR/generated"/*/; do
    domain=$(basename "$domain_dir")
    stop_domain "$domain"
  done

  log_success "Domain shutdown complete"
fi

