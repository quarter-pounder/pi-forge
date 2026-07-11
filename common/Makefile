.ONESHELL:
SHELL := /bin/bash
.SILENT:
.DEFAULT_GOAL := help

.PHONY: help check-env-file env generate-metadata commit-metadata diff-metadata metadata-check drift-check validate lint validate-schema render render-only render-diff deploy deploy-only restart logs ps clean diff-rendered status-domain validate-domain render-all deploy-all list-domains down destroy manifest check-ansible-vault check-vault-file-exists vault-create vault-edit vault-view check-secrets status check-dependencies check-domain-running update update-all update-check dns-fix

ENV ?= dev
DOMAIN ?= forgejo
ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))/..
export ROOT_DIR
PYTHON ?= python3
METADATA_SCRIPT := $(ROOT_DIR)/common/metadata.py
VAULT_FILE := $(ROOT_DIR)/config-registry/env/secrets.env.vault
VAULT_PASS := $(ROOT_DIR)/.vault_pass

BACKUP_SCRIPT := $(ROOT_DIR)/common/scripts/backup.sh
BACKUP_ENV := PIHOLE_API_TOKEN

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "}; \
		/^[a-zA-Z0-9_-]+:.*## / { printf "  make %-38s - %s\n", $$1, $$2 } \
		/^##@/ { printf "\n%s\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Domain Lifecycle

check-env-file:
	@if [ ! -f "$(ROOT_DIR)/.env" ]; then \
		echo "[Env][err] .env not found; copy config-registry/env/base.env to .env and customize it"; \
		exit 1; \
	fi

define LOAD_ENV
	@if [ -f "$(ROOT_DIR)/.env" ]; then \
		set -a; \
		. "$(ROOT_DIR)/config-registry/env/base.env"; \
		. "$(ROOT_DIR)/.env"; \
		set +a; \
	fi
endef

env: check-env-file ## Load environment variables for ENV
	@echo "[Env] Loading environment $(ENV)"
	@cd $(ROOT_DIR) && set -a && . config-registry/env/base.env && . .env && set +a

generate-metadata: ## Generate metadata cache files
	@cd $(ROOT_DIR) && $(PYTHON) $(METADATA_SCRIPT) generate

commit-metadata: ## Review and commit metadata changes
	@cd $(ROOT_DIR) && $(PYTHON) $(METADATA_SCRIPT) commit

diff-metadata: ## Check for metadata drift
	@cd $(ROOT_DIR) && $(PYTHON) $(METADATA_SCRIPT) diff

metadata-check: ## Generate metadata and fail on drift
	@cd $(ROOT_DIR) && $(PYTHON) $(METADATA_SCRIPT) check

drift-check: ## Fail CI if metadata drift detected
	@cd $(ROOT_DIR) && $(PYTHON) $(METADATA_SCRIPT) check || ( \
		echo "[CI] Metadata drift detected — run 'make diff-metadata' locally" && exit 1)
	@echo "[CI] Metadata drift check passed"

validate: metadata-check ## Runtime validation (fast, minimal)
	@cd $(ROOT_DIR) && bash common/validate.sh

lint: validate ## Alias for validate
	@echo "[Lint] Validation completed"

validate-schema: ## Schema validation (CI enforcement)
	@echo "[Validate] Schema validation (CI enforcement)"
	@cd $(ROOT_DIR) && \
	if ! command -v ajv >/dev/null 2>&1; then \
		echo "[WARN] ajv not found — skipping schema validation"; \
		echo "Install: npm install -g ajv-cli"; \
		exit 0; \
	fi; \
	for schema in $(basename $(wildcard config-registry/schema/*.schema.yml)); do \
		yq -o=json config-registry/env/$${schema}.yml | \
		ajv validate -s config-registry/schema/$${schema}.schema.yml || exit 1; \
	done

render: validate render-only ## Render DOMAIN for ENV, with validation (DRY_RUN=1 for dry run)

render-only: check-env-file ## Render DOMAIN for ENV, without validation
	@echo "[Render] $(DOMAIN) for $(ENV)"
	@cd $(ROOT_DIR) && $(PYTHON) common/render_config.py --domain $(DOMAIN) --env $(ENV) $(if $(DRY_RUN),--dry-run)

render-diff: ## Show diff of rendered files for DOMAIN
	@echo "[Render][Diff] $(DOMAIN)"
	@if [ ! -d "$(ROOT_DIR)/generated/$(DOMAIN)" ]; then \
		echo "[Render][Diff][err] No generated files found for $(DOMAIN)"; \
		exit 1; \
	fi
	@cd $(ROOT_DIR) && git diff --no-index generated/$(DOMAIN) generated/$(DOMAIN) 2>/dev/null || \
		git diff generated/$(DOMAIN) 2>/dev/null || \
		echo "[Render][Diff][info] No differences detected"

check-domain-running: ## Check if CHECK_DOMAIN has running containers
	@if [ -z "$(CHECK_DOMAIN)" ]; then \
		echo "[Check][err] CHECK_DOMAIN required (e.g., make check-domain-running CHECK_DOMAIN=postgres)"; \
		exit 1; \
	fi
	@cd $(ROOT_DIR) && $(PYTHON) common/scripts/domain_deps.py is-running $(CHECK_DOMAIN)

check-dependencies: ## Check if DOMAIN's required dependencies are running
	@if [ -f "$(ROOT_DIR)/config-registry/env/domains.yml" ]; then \
		cd $(ROOT_DIR) && \
		REQUIRED=$$($(PYTHON) common/scripts/domain_deps.py requires $(DOMAIN)); \
		if [ -n "$$REQUIRED" ]; then \
			MISSING=""; \
			for dep in $$REQUIRED; do \
				$(MAKE) -s check-domain-running CHECK_DOMAIN=$$dep 2>/dev/null || MISSING="$$MISSING $$dep"; \
			done; \
			if [ -n "$$MISSING" ]; then \
				echo "[Deploy][ERR] Cannot deploy $(DOMAIN): required dependencies are not running:"; \
				for dep in $$MISSING; do \
					echo "[Deploy][ERR]   - $$dep (run 'make deploy DOMAIN=$$dep' first)"; \
				done; \
				echo "[Deploy][ERR] Use FORCE_DEPLOY=1 to override (not recommended)"; \
				if [ "$${FORCE_DEPLOY:-}" != "1" ]; then \
					exit 1; \
				else \
					echo "[Deploy][WARN] FORCE_DEPLOY=1 set, proceeding despite missing dependencies..."; \
				fi; \
			fi; \
		fi; \
	fi

deploy: render check-dependencies ## Render and deploy DOMAIN (FORCE_RECREATE=1 to force recreate)
	@echo "[Deploy] $(DOMAIN)"
	@[ -f "$(ROOT_DIR)/generated/$(DOMAIN)/compose.yml" ] || { echo "[Deploy][err] compose.yml not found for $(DOMAIN)"; exit 1; }
	@cd $(ROOT_DIR) && docker compose -f generated/$(DOMAIN)/compose.yml up -d --pull always $(if $(FORCE_RECREATE),--force-recreate)
	@bash $(ROOT_DIR)/common/scripts/alert-suppression-marker.sh disable $(DOMAIN)

deploy-only: check-dependencies ## Deploy DOMAIN without rendering
	@echo "[Deploy] $(DOMAIN) (no render)"
	@[ -f "$(ROOT_DIR)/generated/$(DOMAIN)/compose.yml" ] || { echo "[Deploy][err] compose.yml not found for $(DOMAIN)"; exit 1; }
	@cd $(ROOT_DIR) && docker compose -f generated/$(DOMAIN)/compose.yml up -d --pull always $(if $(FORCE_RECREATE),--force-recreate)
	@bash $(ROOT_DIR)/common/scripts/alert-suppression-marker.sh disable $(DOMAIN)

restart: check-dependencies ## Restart DOMAIN containers
	@echo "[Restart] $(DOMAIN)"
	@[ -f "$(ROOT_DIR)/generated/$(DOMAIN)/compose.yml" ] || { echo "[Restart][err] compose.yml not found for $(DOMAIN)"; exit 1; }
	@cd $(ROOT_DIR) && docker compose -f generated/$(DOMAIN)/compose.yml restart

logs: ## Show logs for DOMAIN containers
	@echo "[Logs] $(DOMAIN)"
	@[ -f "$(ROOT_DIR)/generated/$(DOMAIN)/compose.yml" ] || { echo "[Logs][err] compose.yml not found for $(DOMAIN)"; exit 1; }
	@cd $(ROOT_DIR) && docker compose -f generated/$(DOMAIN)/compose.yml logs -f

ps: ## Show container status for DOMAIN
	@echo "[PS] $(DOMAIN)"
	@[ -f "$(ROOT_DIR)/generated/$(DOMAIN)/compose.yml" ] || { echo "[PS][err] compose.yml not found for $(DOMAIN)"; exit 1; }
	@cd $(ROOT_DIR) && docker compose -f generated/$(DOMAIN)/compose.yml ps

clean: ## Remove generated files for DOMAIN
	@echo "[Clean] $(DOMAIN)"
	@if [ -d "$(ROOT_DIR)/generated/$(DOMAIN)" ]; then \
		rm -rf "$(ROOT_DIR)/generated/$(DOMAIN)"; \
		echo "[Clean][ok] Removed generated/$(DOMAIN)"; \
	else \
		echo "[Clean][info] No generated files found for $(DOMAIN)"; \
	fi

diff-rendered: ## Diff rendered files vs git for DOMAIN
	@echo "[Diff] Rendered files for $(DOMAIN)"
	@if [ ! -d "$(ROOT_DIR)/generated/$(DOMAIN)" ]; then \
		echo "[Diff][err] No generated files found for $(DOMAIN)"; \
		exit 1; \
	fi
	@cd $(ROOT_DIR) && git diff generated/$(DOMAIN) || echo "[Diff][info] No differences detected"

status-domain: ## Show status for a specific DOMAIN
	@echo "[Status] $(DOMAIN)"
	@if [ -f "$(ROOT_DIR)/generated/$(DOMAIN)/compose.yml" ]; then \
		echo "[Status] Containers:"; \
		cd $(ROOT_DIR) && docker compose -f generated/$(DOMAIN)/compose.yml ps; \
	else \
		echo "[Status][info] Domain not rendered"; \
	fi
	@if [ -d "$(ROOT_DIR)/domains/$(DOMAIN)" ]; then \
		echo "[Status] Domain metadata:"; \
		cat "$(ROOT_DIR)/domains/$(DOMAIN)/metadata.yml" 2>/dev/null || echo "[Status][info] No metadata.yml found"; \
	else \
		echo "[Status][err] Domain $(DOMAIN) not found"; \
	fi

validate-domain: ## Validate a specific DOMAIN's structure
	@echo "[Validate] $(DOMAIN)"
	@if [ ! -d "$(ROOT_DIR)/domains/$(DOMAIN)" ]; then \
		echo "[Validate][err] Domain $(DOMAIN) not found"; \
		exit 1; \
	fi
	@if [ ! -f "$(ROOT_DIR)/domains/$(DOMAIN)/metadata.yml" ]; then \
		echo "[Validate][err] metadata.yml not found for $(DOMAIN)"; \
		exit 1; \
	fi
	@echo "[Validate][ok] Domain $(DOMAIN) structure valid"

list-domains: ## List available domains
	@echo "[List] Available domains:"
	@cd $(ROOT_DIR) && \
		for domain in domains/*/; do \
			domain_name=$$(basename $$domain); \
			if [ -f "$$domain/metadata.yml" ]; then \
				echo "  - $$domain_name"; \
			fi; \
		done

render-all: check-env-file ## Render all domains for ENV
	@echo "[Render][All] Rendering all domains for $(ENV)"
	@cd $(ROOT_DIR) && \
		for domain in domains/*/; do \
			domain_name=$$(basename $$domain); \
			if [ -f "$$domain/metadata.yml" ]; then \
				echo "[Render][All] Rendering $$domain_name..."; \
				$(PYTHON) common/render_config.py --domain $$domain_name --env $(ENV) || echo "[Render][All][warn] Failed to render $$domain_name"; \
			fi; \
		done
	@echo "[Render][All] Completed"

deploy-all: ## Deploy all domains
	@echo "[Deploy][All] Deploying all domains"
	@cd $(ROOT_DIR) && \
		for domain in domains/*/; do \
			domain_name=$$(basename $$domain); \
			if [ -f "$$domain/metadata.yml" ] && [ -f "generated/$$domain_name/compose.yml" ]; then \
				echo "[Deploy][All] Deploying $$domain_name..."; \
				docker compose -f generated/$$domain_name/compose.yml up -d --pull always $(if $(FORCE_RECREATE),--force-recreate) || echo "[Deploy][All][warn] Failed to deploy $$domain_name"; \
			fi; \
		done
	@echo "[Deploy][All] Completed"

UPDATE_SCRIPT := $(ROOT_DIR)/common/scripts/update-domains.sh

update-check: ## Check for available updates (all domains if DOMAIN unset)
	@bash $(UPDATE_SCRIPT) check $(if $(DOMAIN),$(DOMAIN),)

update: ## Apply updates for DOMAIN
	@if [ -z "$(DOMAIN)" ]; then \
		echo "[Update][err] DOMAIN required (e.g., make update DOMAIN=forgejo)"; \
		exit 1; \
	fi
	@bash $(UPDATE_SCRIPT) apply $(DOMAIN)

update-all: ## Apply updates for all domains
	@bash $(UPDATE_SCRIPT) apply-all

down: ## Bring DOMAIN down (warns on critical/dependent domains, FORCE=1 to override)
	@echo "[Down] $(DOMAIN)"
	@[ -f "$(ROOT_DIR)/generated/$(DOMAIN)/compose.yml" ] || { echo "[Down][err] compose.yml not found for $(DOMAIN)"; exit 1; }
	@cd $(ROOT_DIR) && \
	CRITICAL_DOMAINS="monitoring postgres forgejo"; \
	if echo "$$CRITICAL_DOMAINS" | grep -q "^$(DOMAIN)$$" || echo "$$CRITICAL_DOMAINS" | grep -q " $(DOMAIN)$$"; then \
		echo "[Down][WARN] $(DOMAIN) is a critical service. Bringing it down may affect other services."; \
		echo "[Down][WARN] Press Ctrl+C within 5 seconds to cancel..."; \
		sleep 5; \
	fi; \
	DEPENDENTS=$$($(PYTHON) common/scripts/domain_deps.py dependents $(DOMAIN)); \
	if [ -n "$$DEPENDENTS" ]; then \
		echo "[Down][ERR] Cannot bring down $(DOMAIN): other domains depend on it:"; \
		for dep in $$DEPENDENTS; do \
			echo "[Down][ERR]   - $$dep"; \
		done; \
		echo "[Down][ERR] Bring down dependent domains first, or use FORCE=1 to override"; \
		if [ "$$FORCE" != "1" ]; then \
			exit 1; \
		else \
			echo "[Down][WARN] FORCE=1 set, proceeding despite dependencies..."; \
		fi; \
	fi; \
	echo "[Down] Bringing down $(DOMAIN)..."; \
	docker compose -f generated/$(DOMAIN)/compose.yml down; \
	bash common/scripts/alert-suppression-marker.sh enable $(DOMAIN)

destroy: ## Destroy DOMAIN (removes volumes)
	@echo "[Destroy] $(DOMAIN)"
	@[ -f "$(ROOT_DIR)/generated/$(DOMAIN)/compose.yml" ] || { echo "[Destroy][err] compose.yml not found for $(DOMAIN)"; exit 1; }
	@cd $(ROOT_DIR) && docker compose -f generated/$(DOMAIN)/compose.yml down -v

manifest: ## Generate manifest
	@echo "[Manifest] Generating manifest..."
	@cd $(ROOT_DIR) && bash common/generate-manifest.sh || echo "Manifest generation not yet implemented"

##@ Vault Management

check-ansible-vault:
	@command -v ansible-vault >/dev/null 2>&1 || { echo "[Vault][err] ansible-vault not installed"; exit 1; }

check-vault-file-exists:
	@[ -f "$(VAULT_FILE)" ] || { echo "[Vault][err] secrets.env.vault missing"; exit 1; }

vault-create: check-ansible-vault ## Create secrets.env.vault (uses .vault_pass when present)
	@cd $(ROOT_DIR) && \
	if [ -f config-registry/env/secrets.env.vault ]; then \
		echo "[Vault][warn] secrets.env.vault already exists"; exit 1; \
	fi; \
	if [ -f .vault_pass ]; then \
		ansible-vault create config-registry/env/secrets.env.vault --vault-password-file .vault_pass; \
	else \
		ansible-vault create config-registry/env/secrets.env.vault; \
	fi

vault-edit: check-ansible-vault check-vault-file-exists ## Edit secrets.env.vault
	@cd $(ROOT_DIR) && \
	if [ -f .vault_pass ]; then \
		ansible-vault edit config-registry/env/secrets.env.vault --vault-password-file .vault_pass; \
	else \
		ansible-vault edit config-registry/env/secrets.env.vault; \
	fi

vault-view: check-ansible-vault check-vault-file-exists ## View secrets.env.vault contents
	@cd $(ROOT_DIR) && \
	if [ -f .vault_pass ]; then \
		ansible-vault view config-registry/env/secrets.env.vault --vault-password-file .vault_pass; \
	else \
		ansible-vault view config-registry/env/secrets.env.vault; \
	fi

check-secrets: ## Check vault file and password file status
	@cd $(ROOT_DIR) && \
	missing=0; \
	if [ ! -f "$(VAULT_FILE)" ]; then \
		echo "[Vault][warn] $(VAULT_FILE) missing — templates may lack secrets"; \
		missing=1; \
	fi; \
	if [ -f "$(VAULT_PASS)" ]; then \
		if [ ! -s "$(VAULT_PASS)" ]; then \
			echo "[Vault][warn] $(VAULT_PASS) exists but is empty"; \
			missing=1; \
		fi; \
	else \
		echo "[Vault][info] .vault_pass not found — ansible-vault will prompt interactively"; \
	fi; \
	if [ $$missing -eq 0 ]; then \
		echo "[Vault][ok] secrets vault ready"; \
	fi

##@ Status & Utilities

status: ## Show overall system status
	@echo "[Status] Metadata diff:"
	@$(MAKE) -s diff-metadata || true
	@$(MAKE) -s check-secrets || true
	@echo "[Status] Rendered domains:"
	@ls -1 $(ROOT_DIR)/generated 2>/dev/null || echo "(none)"

DNS_FIX_SCRIPT := $(ROOT_DIR)/common/scripts/configure-dns-fallback.sh

dns-fix: ## Run DNS fallback one-time fix (requires sudo)
	@echo "[DNS Fix] Configuring host DNS fallback (systemd-resolved, resolv.conf)..."
	@[ -f "$(DNS_FIX_SCRIPT)" ] || { echo "[DNS Fix][err] Script not found: $(DNS_FIX_SCRIPT)"; exit 1; }
	@cd $(ROOT_DIR) && sudo bash "$(DNS_FIX_SCRIPT)"

.PHONY: add-github-runner github-runner-down destroy-github-runner list-github-runners render-github-runner deploy-github-runner
GITHUB_RUNNER_MANAGER := $(ROOT_DIR)/common/scripts/github-runner-manager.sh

##@ GitHub Actions Runner Management

add-github-runner: ## Add a runner (NAME=, REPO_URL=, TOKEN=, [LABELS=], [DOCKER_ENABLED=])
	@if [ -z "$(NAME)" ]; then \
		echo "[GitHub Runner][err] NAME required"; \
		echo "Usage: make add-github-runner NAME=<name> REPO_URL=<url> TOKEN=<token> [LABELS=<labels>] [DOCKER_ENABLED=true]"; \
		exit 1; \
	fi
	@bash $(GITHUB_RUNNER_MANAGER) add $(NAME) \
		--repo-url "$(REPO_URL)" \
		--token "$(TOKEN)" \
		$(if $(LABELS),--labels "$(LABELS)",) \
		$(if $(DOCKER_ENABLED),--docker-enabled "$(DOCKER_ENABLED)",)

github-runner-down: ## Bring down a runner (NAME=)
	@if [ -z "$(NAME)" ]; then \
		echo "[GitHub Runner][err] NAME required (e.g., make github-runner-down NAME=pi-runner)"; \
		exit 1; \
	fi
	@bash $(GITHUB_RUNNER_MANAGER) down $(NAME)

destroy-github-runner: ## Destroy a runner, removes data (NAME=)
	@if [ -z "$(NAME)" ]; then \
		echo "[GitHub Runner][err] NAME required (e.g., make destroy-github-runner NAME=pi-runner)"; \
		exit 1; \
	fi
	@bash $(GITHUB_RUNNER_MANAGER) destroy $(NAME)

list-github-runners: ## List all configured runners
	@bash $(GITHUB_RUNNER_MANAGER) list

render-github-runner: ## Render compose file for a runner (NAME=)
	@if [ -z "$(NAME)" ]; then \
		echo "[GitHub Runner][err] NAME required (e.g., make render-github-runner NAME=pi-runner)"; \
		exit 1; \
	fi
	@bash $(GITHUB_RUNNER_MANAGER) render $(NAME)

deploy-github-runner: ## Deploy a runner (NAME=)
	@if [ -z "$(NAME)" ]; then \
		echo "[GitHub Runner][err] NAME required (e.g., make deploy-github-runner NAME=pi-runner)"; \
		exit 1; \
	fi
	@bash $(GITHUB_RUNNER_MANAGER) deploy $(NAME)

.PHONY: backup backup-cloud backup-prune

##@ Backup Management

backup: ## Run full backup (local or cloud based on BACKUP_MODE)
	$(LOAD_ENV)
	@BACKUP_MODE=$${BACKUP_MODE:-manual} bash $(BACKUP_SCRIPT)

backup-prune: ## Prune old backup snapshots
	$(LOAD_ENV)
	@BACKUP_MODE=prune BACKUP_PRUNE=1 bash $(BACKUP_SCRIPT)

backup-cloud: ## Run cloud backup (requires RESTIC_REMOTE)
	$(LOAD_ENV)
	@if [ -z "$${RESTIC_REMOTE:-}" ]; then \
		echo "[Backup][err] RESTIC_REMOTE not set (define in .env)"; \
		exit 1; \
	fi; \
	BACKUP_MODE=cloud RESTIC_REPOSITORY="$${RESTIC_REMOTE}" bash $(BACKUP_SCRIPT)
