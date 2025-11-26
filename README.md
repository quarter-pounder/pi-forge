# Pi Forge

## Overview
Pi Forge rebuilds a former GitLab-centric Raspberry Pi homelab into a domain-driven deployment stack.
Every domain—Forgejo, PostgreSQL, Woodpecker, monitoring, adblocker, registry is rendered from Jinja templates and deployed via Docker Compose.
Configuration is declarative; generated artifacts live under `generated/` and are never committed.
The old maze of scripts lives in the `legacy` branch for keepsake. For more details, see `docs/story-behind.md`

## Configuration Registry
This repo centralizes configuration so templates always render from a single source of truth:
- `config-registry/env/base.env`: shared values (timezone, domain, image tags)
- Overrides in `config-registry/env/overrides/<env>.env`
- Secrets encrypted in `config-registry/env/secrets.env.vault`
- Declarative topology in:
  - `domains.yml`: which domains exist and what they depend on
  - `ports.yml`: consistent port naming (`PORT_<DOMAIN>_<NAME>`)

Flow:

1. `make generate-metadata` produces canonical metadata in `state/metadata-cache/<domain>.yml`
2. `make diff-metadata` shows drift against committed metadata
3. `make commit-metadata` promotes metadata into `domains/<domain>/metadata.yml`
4. `make render DOMAIN=<name>` turns metadata → Jinja → runnable config under `generated/<name>/`
5. `make deploy DOMAIN=<name>` applies the domain; `make destroy DOMAIN=<name>` tears it down safely
6. `make validate` provides fast structural checks; `make validate-schema` enforces JSON schema in CI; `tools/metadata_watchdog.py` can run as a daemon to surface drift whenever cached metadata changes.

Templates are clean. Metadata is authoritative. Everything else is disposable.

## Current Status

All core domains are deployed and operational:

- Forgejo (with Actions runner)
- PostgreSQL (Forgejo + Woodpecker)
- Woodpecker server and runner
- Monitoring stack: Prometheus, Alertmanager, Loki, Grafana dashboards
- Adblocker
- Container registry
- Cloudflare tunnel
- Host telemetry via cron (temperature, throttling, voltage)

Everything passes health checks and dashboards render correctly.

Optional follow-ups:
- SMTP testing for alerts
- Restic cloud backup verification
- Terraform landing zone for disaster recovery

## Backups & Disaster Recovery

Backups use restic (encrypted, deduplicated). Included:

- Forgejo data
- Woodpecker data
- PostgreSQL dumps
- Monitoring + Grafana
- Registry
- Adblocker
- secrets vault

Restores are tested. Long-term DR goal: move Forgejo + CI to the cloud using managed Postgres and object storage, with on-demand container runtime.

## Documentation
- Domain specifics: `docs/domains/*.md`
- Operations: `docs/operations/*.md`
- Rebuild notes: `rebuild-plan.md` and `rebuild-steps.md`

Run `make help` for common targets or consult `common/Makefile` for the full workflow targets.

## Design Principles

- No mystery states: everything is declared or generated
- No hand-edited YAML: templates own the output
- No silent drift: metadata diffing is mandatory
- No snowflake hosts: restore and rebuild should always work
- No heroism: if a workflow requires bravery, rewrite the workflow

This repo exists so future me doesn’t have to remember anything except where the repo is.

