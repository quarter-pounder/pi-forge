# Bootstrap

> Initializes a clean Ubuntu host into a Docker-ready Raspberry Pi environment.
Tested on Ubuntu 22.04 LTS / 24.04 LTS (ARM64, Raspberry Pi 5 8GB).

## Overview

Bootstrap prepares an Ubuntu installation for the pi-forge stack. It installs core packages, sets up Docker, tunes Docker for Raspberry Pi performance, and validates the full environment.

All scripts are idempotent except the 00-* migration helpers.
Re-running normal bootstrap steps will not overwrite user data or damage an existing setup.

## Scripts

### Execution Order

```mermaid
graph TD
  subgraph Optional["Optional - NVMe preparation"]
    A[00 - Flash NVMe (fresh image)]
    B[00 - Clone SD → NVMe (live)]
  end
  C[01 - Preflight Checks]
  D[02 - Install Core Packages]
  E[03 - Install Docker]
  F[04 - Optimize Docker]
  G[05 - Verify Setup]
  H[06 - Security Hardening]
  A --> C
  B --> C
```

> **Reality check:** the 00-* scripts behave more like homemade Pi Imager in bash. They work, but cloning a running SD-card rootfs to NVMe is inherently brittle. Flashing Ubuntu directly onto NVMe with Raspberry Pi Imager (or Etcher) is always the better path. The scripts exist so to make it clear that this is optional and not the recommended route.

1. **`00-migrate-to-nvme.sh`** (Optional)
   - Writes a fresh Ubuntu image to an NVMe drive (non-idempotent)
   - Generates cloud-init data from `config-registry/env/base.env` when available
   - Verifies SHA256, updates EEPROM boot order
   - Overwrites the entire device; treat it as a one-shot imaging tool

1. **`00-nvme-migrate-live.sh`** (Optional, fragile)
   - Attempts to clone a running SD installation onto NVMe with `rsync`
   - Preserves `/etc/fstab`, `/boot/firmware`, swapfiles, Alertmanager markers, etc.
   - Performs extensive validation (fsck, PARTUUID swap, label checks) before updating boot order
   - **Not idempotent:** any writes during the copy can corrupt the target; use only if you can’t take the Pi offline to flash a fresh image

1. **`01-preflight.sh`**
   - Sanity-checks the base OS only (Ubuntu release, architecture, RAM, disk space, connectivity, sudo)
   - Warns about missing values in `config-registry/env/base.env` but does **not** require it
   - Designed to run before any packages are installed, so no tooling checks happen here

1. **`02-install-core.sh`**
   - Installs core system dependencies
   - Packages: `curl`, `wget`, `git`, `jq`, `yq` (Go build), `gettext-base`, `ansible`, `rsync`, `htop`, `vim`, `unzip`, `ca-certificates`, `gnupg`, `lsb-release`, `software-properties-common`
   - Raspberry Pi specific: `rpi-eeprom`, `nvme-cli`, `util-linux`, `dosfstools`, `e2fsprogs`, `parted`, `pv`
   - Requires: sudo

1. **`03-install-docker.sh`**
   - Installs Docker Engine and Docker Compose
   - Adds current user to `docker` group
   - Enables Docker service (does not start yet)
   - Requires: sudo
   - **Note:** Docker daemon configuration is handled by `04-optimize-docker.sh`

1. **`04-optimize-docker.sh`**
   - Configures Docker daemon for optimal Raspberry Pi performance
   - Settings: `overlay2` storage driver, log rotation, IP pools, `live-restore`, disabled `userland-proxy`, optimized ulimits
   - Backs up existing `daemon.json` if present
   - Starts and verifies Docker daemon
   - Requires: root privileges (uses `require_root`)

1. **`05-verify.sh`**
   - Comprehensive verification of bootstrap installation
   - Checks: Docker installation, Docker Compose, daemon status, group membership, functionality
   - Validates: tools, `/srv` directory and mount point, disk space, memory/swap, storage driver, network interfaces
   - Optional: disk throughput test (skip with `SKIP_THROUGHPUT_TEST=1`)
   - Requires: none (some checks use sudo internally)

1. **`06-security-hardening.sh`** (Optional but recommended)
   - SSH hardening (disables password login, restricts users)
   - fail2ban with conservative defaults
   - Enables unattended security upgrades
   - Applies kernel/sysctl hardening flags
   - Requires: sudo (installs/updates configs under `/etc`)

## Quick Start (Manual Execution)

```bash

git clone <repo-url> pi-forge
cd pi-forge

# Bootstrap
sudo bash bootstrap/01-preflight.sh
sudo bash bootstrap/02-install-core.sh
sudo bash bootstrap/03-install-docker.sh
sudo bash bootstrap/04-optimize-docker.sh
bash bootstrap/05-verify.sh
sudo bash bootstrap/06-security-hardening.sh

# Re-login to pick up docker group membership
```

## Dependencies & Requirements

Runs on Ubuntu 22.04+ ARM64 with no prerequisites besides apt and sudo.
All required dependencies are installed during bootstrap.

| Component | Provided by | Notes |
|------------|--------------|-------|
| Basic tools (`curl`, `git`, `wget`) | `02-install-core.sh` | Needed for downloads and cloning |
| Package manager (`apt`, `sudo`) | Ubuntu default | Checked before execution |
| Optional environment (`base.env`) | User-defined | Used for cloud-init or pre-seeding |

## Configuration

### Pre-configure Environment (Optional)

If `config-registry/env/base.env` exists before running bootstrap:

- `01-preflight.sh` will load and validate it
- `00-migrate-to-nvme.sh` will use it for cloud-init configuration
- Otherwise, bootstrap runs with defaults

After bootstrap, re-login so Docker group membership takes effect

### Secrets (Vault)

- Generate `.vault_pass` at repository root before rendering configuration
- Manage encrypted variables with `make vault-create`, `make vault-edit`, and `make vault-view`
- More details: `docs/operations/secrets.md`

## Logging

- Migration logs: /var/log/nvme-migrate.log
- All scripts use the same logging helpers (log_info, log_warn, etc.)
- Color output: Enabled for TTY, disabled for non-TTY

## Error Handling

- All scripts use strict mode: `set -Eeuo pipefail`
- INT/TERM traps for graceful exit
- Migration scripts include cleanup traps
- Scripts fail fast on errors with clear error messages
- Verification prints actionable diagnostics

## Troubleshooting

### Docker Group Membership

`docker ps` requires sudo:

```bash
# Logout and login, or:
newgrp docker
```

### Disk Space Issues

If verification fails due to disk space:

- Ensure `/srv` is mounted on NVMe (not root filesystem)
- Check free space: `df -h /srv`
- Minimum recommended: 50GB+

### Network Issues

If package installation fails:

- Test connectivity
- Test DNS resolution
- Inspect apt sources and netplan configuration

### NVMe Migration Failures

If migration script fails:

- Check detection: `lsblk | grep nvme`
- Check device size: `lsblk -o NAME,SIZE,TYPE | grep nvme`
- Ensure sufficient space for image download (4GB+)
- Check logs: `tail -f /var/log/nvme-migrate.log`

## Files

- `utils.sh` - shared helpers
- `00-migrate-to-nvme.sh` & `00-nvme-migrate-live.sh` - NVMe imaging/migration
- `01-preflight.sh` - environment checks
- `02-install-core.sh` - dependency installation
- `03-install-docker.sh` - Docker installation
- `04-optimize-docker.sh` - daemon tuning
- `05-verify.sh` - validation
- `06-security-hardening.sh` - SSH/fail2ban/sysctl hardening

## Design Principles

1. Bootstrap remains self-contained (no dependency on domains or config-registry)
2. Only essential packages are installed
3. **Idempotency:** 01–06 may be re-run safely at any time
4. **Fail Fast:** noisy errors, early exits
5. **Verification:** Checks at each step
