#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

source "$ROOT_DIR/common/utils.sh" 2>/dev/null || {
  log_error() { echo "[ERROR] $*" >&2; }
  log_info() { echo "[INFO] $*"; }
  log_success() { echo "[OK] $*"; }
  log_warn() { echo "[WARN] $*" >&2; }
}

require_root

RESOLVED_CONF="/etc/systemd/resolved.conf"
BACKUP_CONF="${RESOLVED_CONF}.bak.$(date +%Y%m%d_%H%M%S)"

log_info "Configuring systemd-resolved with DNS fallback..."

if [[ -f "$RESOLVED_CONF" ]]; then
  cp "$RESOLVED_CONF" "$BACKUP_CONF"
  log_info "Backed up existing config to $BACKUP_CONF"
fi

if grep -q "^FallbackDNS=" "$RESOLVED_CONF" 2>/dev/null; then
  log_info "Fallback DNS already configured"
else
  if grep -q "^\[Resolve\]" "$RESOLVED_CONF" 2>/dev/null; then
    if ! grep -q "^FallbackDNS=" "$RESOLVED_CONF" 2>/dev/null; then
      sed -i '/^\[Resolve\]/a FallbackDNS=1.1.1.1 8.8.8.8 1.0.0.1' "$RESOLVED_CONF"
      log_success "Added fallback DNS to existing [Resolve] section"
    fi
  else
    echo "" >> "$RESOLVED_CONF"
    echo "[Resolve]" >> "$RESOLVED_CONF"
    echo "FallbackDNS=1.1.1.1 8.8.8.8 1.0.0.1" >> "$RESOLVED_CONF"
    log_success "Added [Resolve] section with fallback DNS"
  fi
fi

if grep -q "^DNSStubListener=yes" "$RESOLVED_CONF" 2>/dev/null; then
  sed -i 's/^DNSStubListener=yes/DNSStubListener=no/' "$RESOLVED_CONF"
  log_info "Disabled DNSStubListener to allow pihole to use port 53"
elif ! grep -q "^DNSStubListener=" "$RESOLVED_CONF" 2>/dev/null; then
  if grep -q "^\[Resolve\]" "$RESOLVED_CONF" 2>/dev/null; then
    sed -i '/^\[Resolve\]/a DNSStubListener=no' "$RESOLVED_CONF"
    log_info "Set DNSStubListener=no to allow pihole to use port 53"
  fi
fi

log_info "Restarting systemd-resolved..."
systemctl restart systemd-resolved

RESOLV_CONF="/etc/resolv.conf"
RESOLVED_RESOLV="/run/systemd/resolve/resolv.conf"
if [[ -L "$RESOLV_CONF" ]]; then
  TARGET=$(readlink "$RESOLV_CONF")
  if [[ "$TARGET" == *stub-resolv.conf* ]]; then
    log_info "Pointing /etc/resolv.conf to resolved upstream list (not stub)..."
    ln -sfn "$RESOLVED_RESOLV" "$RESOLV_CONF"
    log_success "Updated resolv.conf symlink"
  fi
fi

if [[ -f "$RESOLV_CONF" ]]; then
  if grep -q "127.0.0.53\|127.0.0.1\|::1" "$RESOLV_CONF" 2>/dev/null && ! grep -q "1.1.1.1\|8.8.8.8" "$RESOLV_CONF" 2>/dev/null; then
    log_warn "resolv.conf still points to localhost; writing static fallback nameservers"
    echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > "$RESOLV_CONF"
    log_success "Wrote fallback nameservers to $RESOLV_CONF"
  fi
elif [[ ! -e "$RESOLV_CONF" ]]; then
  log_warn "No $RESOLV_CONF; creating with fallback nameservers"
  echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > "$RESOLV_CONF"
  log_success "Created $RESOLV_CONF"
fi

log_success "DNS fallback configured"
log_info "Fallback DNS servers: 1.1.1.1, 8.8.8.8, 1.0.0.1"
log_info "Host will resolve via these when adblocker (port 53) is down or starting"

