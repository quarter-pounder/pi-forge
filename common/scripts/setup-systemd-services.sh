#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/../.."
source "$(dirname "$0")/../utils.sh" 2>/dev/null || {
  log_error() { echo "[ERROR] $*" >&2; }
  log_info() { echo "[INFO] $*"; }
  log_success() { echo "[OK] $*"; }
  log_warn() { echo "[WARN] $*" >&2; }
}

require_root

REPO_DIR="$(pwd)"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_NAME="pi-forge-domains.service"
UPDATE_SERVICE="pi-forge-update.service"
UPDATE_TIMER="pi-forge-update.timer"

if [[ -f "$REPO_DIR/.env" ]]; then
  set -a
  source "$REPO_DIR/.env" 2>/dev/null || true
  set +a
fi

SERVICE_USER="${USERNAME:-${SUDO_USER:-$USER}}"
if [[ -z "$SERVICE_USER" ]] || [[ "$SERVICE_USER" == "root" ]]; then
  log_error "Could not determine service user. Set USERNAME in .env or run as non-root user with sudo."
  exit 1
fi

log_info "Setting up Pi Forge systemd services (user: $SERVICE_USER)..."

if [[ ! -f "$REPO_DIR/common/scripts/domain-orchestrator.sh" ]]; then
  log_error "domain-orchestrator.sh not found"
  exit 1
fi

chmod +x "$REPO_DIR/common/scripts/domain-orchestrator.sh"
chmod +x "$REPO_DIR/common/scripts/check-lts-updates.sh" 2>/dev/null || true
chmod +x "$REPO_DIR/common/scripts/configure-dns-fallback.sh" 2>/dev/null || true

log_info "Configuring DNS fallback (resilience against adblocker failures)..."
if [[ -f "$REPO_DIR/common/scripts/configure-dns-fallback.sh" ]]; then
  bash "$REPO_DIR/common/scripts/configure-dns-fallback.sh" || log_warn "DNS fallback configuration failed (may need manual setup)"
fi

log_info "Creating domain orchestration service..."

cat > "$SYSTEMD_DIR/$SERVICE_NAME" <<EOF
[Unit]
Description=Pi Forge Domain Orchestration
Documentation=file://$REPO_DIR/README.md
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=$SERVICE_USER
Group=docker
WorkingDirectory=$REPO_DIR
Environment="ROOT_DIR=$REPO_DIR"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$REPO_DIR/common/scripts/domain-orchestrator.sh start
ExecStop=$REPO_DIR/common/scripts/domain-orchestrator.sh stop
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

log_success "Domain orchestration service created"

if [[ -f "$REPO_DIR/common/scripts/check-lts-updates.sh" ]]; then
  log_info "Creating update checker service and timer..."

  cat > "$SYSTEMD_DIR/$UPDATE_SERVICE" <<EOF
[Unit]
Description=Pi Forge LTS Update Checker
Documentation=file://$REPO_DIR/README.md
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
User=$SERVICE_USER
Group=docker
WorkingDirectory=$REPO_DIR
Environment="ROOT_DIR=$REPO_DIR"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$REPO_DIR/common/scripts/check-lts-updates.sh
StandardOutput=journal
StandardError=journal
EOF

  cat > "$SYSTEMD_DIR/$UPDATE_TIMER" <<EOF
[Unit]
Description=Pi Forge LTS Update Check Timer
Documentation=file://$REPO_DIR/README.md
Requires=$UPDATE_SERVICE

[Timer]
OnCalendar=weekly
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF

  log_success "Update checker service and timer created"
fi

log_info "Reloading systemd daemon..."
systemctl daemon-reload

log_info "Enabling domain orchestration service..."
systemctl enable "$SERVICE_NAME"

log_success "Systemd services setup complete"
log_info ""
log_info "Domain orchestration service: $SERVICE_NAME"
log_info "  Status: sudo systemctl status $SERVICE_NAME"
log_info "  Start:  sudo systemctl start $SERVICE_NAME"
log_info "  Logs:   sudo journalctl -u $SERVICE_NAME -f"
log_info ""

if [[ -f "$REPO_DIR/common/scripts/check-lts-updates.sh" ]]; then
  log_info "Update checker timer: $UPDATE_TIMER"
  log_info "  Enable:  sudo systemctl enable --now $UPDATE_TIMER"
  log_info "  Status:  sudo systemctl status $UPDATE_TIMER"
  log_info "  Logs:    sudo journalctl -u $UPDATE_SERVICE -f"
  log_info ""
  log_info "Note: Update timer is disabled by default. Enable it with:"
  log_info "  sudo systemctl enable --now $UPDATE_TIMER"
fi

