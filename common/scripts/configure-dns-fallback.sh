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

# Check if fallback DNS is already configured
if grep -q "^FallbackDNS=" "$RESOLVED_CONF" 2>/dev/null; then
  log_info "Fallback DNS already configured"
else
  # Add fallback DNS if [Resolve] section exists
  if grep -q "^\[Resolve\]" "$RESOLVED_CONF" 2>/dev/null; then
    if ! grep -q "^FallbackDNS=" "$RESOLVED_CONF" 2>/dev/null; then
      sed -i '/^\[Resolve\]/a FallbackDNS=1.1.1.1 8.8.8.8 1.0.0.1' "$RESOLVED_CONF"
      log_success "Added fallback DNS to existing [Resolve] section"
    fi
  else
    # Add [Resolve] section with fallback DNS
    echo "" >> "$RESOLVED_CONF"
    echo "[Resolve]" >> "$RESOLVED_CONF"
    echo "FallbackDNS=1.1.1.1 8.8.8.8 1.0.0.1" >> "$RESOLVED_CONF"
    log_success "Added [Resolve] section with fallback DNS"
  fi
fi

# Ensure DNSStubListener is enabled (default, but check)
if grep -q "^#DNSStubListener=" "$RESOLVED_CONF" 2>/dev/null || ! grep -q "^DNSStubListener=" "$RESOLVED_CONF" 2>/dev/null; then
  if ! grep -q "^DNSStubListener=yes" "$RESOLVED_CONF" 2>/dev/null; then
    if grep -q "^\[Resolve\]" "$RESOLVED_CONF" 2>/dev/null; then
      sed -i '/^\[Resolve\]/a DNSStubListener=yes' "$RESOLVED_CONF"
    fi
  fi
fi

log_info "Restarting systemd-resolved..."
systemctl restart systemd-resolved

log_success "DNS fallback configured"
log_info "Fallback DNS servers: 1.1.1.1, 8.8.8.8, 1.0.0.1"
log_info "These will be used if adblocker (127.0.0.1:53) is unavailable"

