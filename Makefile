HOST       ?= zoe.home.dodwell.us
TARGET     ?= zoe.home.dodwell.us
FLAKE      ?= path:.#zoe
HOST_KEY_PUB := secrets/host-keys/ssh_host_ed25519_key.pub
HOST_KEY_AGE := secrets/ssh_host_ed25519_key.age
EXTRA_FILES  := secrets/host-keys/extra-files

# ─── Deployment ────────────────────────────────────────────────
.PHONY: deploy deploy-nixos deploy-boot deploy-test deploy-dry

## Full deploy: build app locally, sync, migrate DB, apply NixOS config, restart service
deploy: sync-app
	nixos-rebuild switch --flake $(FLAKE) --target-host $(TARGET) --sudo
	ssh $(TARGET) 'sudo systemctl reset-failed paperclip; sudo systemctl restart paperclip'

## NixOS config only (no app build/sync)
deploy-nixos:
	nixos-rebuild switch --flake $(FLAKE) --target-host $(TARGET) --sudo

## Deploy but only activate on next boot
deploy-boot:
	nixos-rebuild boot --flake $(FLAKE) --target-host $(TARGET) --sudo

## Deploy to test (rollback on disconnect)
deploy-test:
	nixos-rebuild test --flake $(FLAKE) --target-host $(TARGET) --sudo

## Dry run — show what would change
deploy-dry:
	nixos-rebuild dry-activate --flake $(FLAKE) --target-host $(TARGET) --sudo

# ─── Build (local) ─────────────────────────────────────────────
.PHONY: build build-vm

## Build the system closure locally
build:
	nixos-rebuild build --flake $(FLAKE)

## Build a QEMU VM for testing
build-vm:
	nixos-rebuild build-vm --flake $(FLAKE)

# ─── Host Key Management ─────────────────────────────────────
.PHONY: generate-host-keys

## Generate SSH host key pair for the NUC (run once before first install)
## Private key is age-encrypted with your user key; public key is plaintext
generate-host-keys:
	@if [ -f $(HOST_KEY_AGE) ]; then \
		echo "Host key already exists at $(HOST_KEY_AGE)"; \
		echo "To regenerate, delete $(HOST_KEY_AGE) and $(HOST_KEY_PUB) first."; \
		exit 1; \
	fi
	@TMPDIR=$$(mktemp -d) && \
	trap 'rm -rf "$$TMPDIR"' EXIT && \
	echo "Generating ed25519 host key pair for paperclip NUC..." && \
	ssh-keygen -t ed25519 -f "$$TMPDIR/ssh_host_ed25519_key" -N "" -C "root@paperclip" && \
	cp "$$TMPDIR/ssh_host_ed25519_key.pub" $(HOST_KEY_PUB) && \
	echo "Encrypting private key with age (user key only — bootstrap secret)..." && \
	age -R ~/.ssh/id_ed25519.pub \
		-o $(HOST_KEY_AGE) "$$TMPDIR/ssh_host_ed25519_key" && \
	echo "" && \
	echo "Generated:" && \
	echo "  Public:  $(HOST_KEY_PUB)  (plaintext, committed)" && \
	echo "  Private: $(HOST_KEY_AGE)  (age-encrypted, committed)" && \
	echo "" && \
	echo "Public key:" && \
	cat $(HOST_KEY_PUB) && \
	echo "" && \
	echo "Next steps:" && \
	echo "  1. make rekey                          # re-encrypt app secrets with host key" && \
	echo "  2. make edit-secret NAME=paperclip-env  # create your secrets" && \
	echo "  3. make install                         # install NixOS on the NUC"

# ─── Initial Install ──────────────────────────────────────────
.PHONY: install install-prepare-extra-files

## Prepare the extra-files tree for nixos-anywhere (host key injection)
## Decrypts the age-encrypted private key into a temp staging tree
install-prepare-extra-files:
	@if [ ! -f $(HOST_KEY_AGE) ]; then \
		echo "ERROR: No host key found. Run 'make generate-host-keys' first."; \
		exit 1; \
	fi
	rm -rf $(EXTRA_FILES)
	mkdir -p $(EXTRA_FILES)/etc/ssh
	age -d -i ~/.ssh/id_ed25519 -o $(EXTRA_FILES)/etc/ssh/ssh_host_ed25519_key $(HOST_KEY_AGE)
	cp $(HOST_KEY_PUB) $(EXTRA_FILES)/etc/ssh/ssh_host_ed25519_key.pub
	chmod 600 $(EXTRA_FILES)/etc/ssh/ssh_host_ed25519_key
	chmod 644 $(EXTRA_FILES)/etc/ssh/ssh_host_ed25519_key.pub

## First-time install via nixos-anywhere (wipes disk!)
## Decrypts host key from .age, injects via --extra-files so agenix works from first boot
install: install-prepare-extra-files
	@echo "WARNING: This will WIPE $(TARGET) and install NixOS from scratch!"
	@echo "Host key will be decrypted from $(HOST_KEY_AGE) and injected"
	@read -p "Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ] || exit 1
	trap 'rm -rf $(EXTRA_FILES); echo "Cleaned up extra-files"' EXIT; \
	nix run github:nix-community/nixos-anywhere -- \
		--flake $(FLAKE) \
		--extra-files $(EXTRA_FILES) \
		$(TARGET)
	@echo ""
	@echo "Install complete. Verify with: make status"

# ─── Fast Iteration (no rebuild) ──────────────────────────────
.PHONY: deploy-app sync-app sync-config

## App-only deploy: build, sync, migrate, restart (no nixos-rebuild)
deploy-app:
	$(MAKE) sync-app
	$(MAKE) restart

## Build app locally then rsync to NUC, then apply pending DB migrations
sync-app:
	cd .. && pnpm install && pnpm build
	rsync -avz --delete \
		-e "ssh -i ~/.ssh/id_agent_paperclip" \
		--exclude node_modules \
		--exclude .git \
		--exclude nix \
		../ agent@$(HOST):/home/agent/paperclip/
	ssh -i ~/.ssh/id_agent_paperclip agent@$(HOST) \
		'cd /home/agent/paperclip && node scripts/apply-publish-config.mjs'
	$(MAKE) db-migrate

## Rsync MCP config
sync-config:
	rsync -avz -e "ssh -i ~/.ssh/id_agent_paperclip" ./mcp-config/ agent@$(HOST):/home/agent/.paperclip/mcp/

# ─── Service Management ───────────────────────────────────────
.PHONY: status restart logs logs-mcp logs-nginx logs-health

## Check service status
status:
	ssh $(TARGET) 'systemctl status paperclip paperclip-mcp-context7 postgresql nginx paperclip-db-backup.timer paperclip-health-check.timer --no-pager'

## Restart paperclip services
restart:
	ssh $(TARGET) 'sudo systemctl restart paperclip'

## Follow paperclip logs
logs:
	ssh $(TARGET) 'journalctl -u paperclip -f'

## Follow MCP server logs
logs-mcp:
	ssh $(TARGET) 'journalctl -u paperclip-mcp-context7 -f'

## Follow nginx logs
logs-nginx:
	ssh $(TARGET) 'journalctl -u nginx -f'

## Show recent health check results
logs-health:
	ssh $(TARGET) 'journalctl -u paperclip-health-check --since "1 hour ago" --no-pager'

# ─── Database ─────────────────────────────────────────────────
.PHONY: db-shell db-migrate db-backup db-restore db-backup-status db-backup-list

## Apply pending Drizzle migrations on the server (idempotent, safe to re-run)
## DATABASE_URL is loaded from /run/paperclip/db-env (generated by the db-env service script).
db-migrate:
	ssh -i ~/.ssh/id_agent_paperclip agent@$(HOST) \
		'set -a && . /run/paperclip/db-env && set +a && cd /home/agent/paperclip && node packages/db/dist/migrate.js'

## Open psql shell on remote (connects as postgres via peer auth)
db-shell:
	ssh -t $(TARGET) 'sudo -u postgres psql paperclip'

## Backup database to local file (manual, on-demand, custom format for consistency)
db-backup:
	ssh $(TARGET) 'sudo -u postgres pg_dump --format=custom paperclip' > backup-$$(date +%Y%m%d-%H%M%S).dump
	@echo "Backup saved to backup-*.dump"

## Restore database from .dump file (usage: make db-restore FILE=backup.dump)
db-restore:
	@[ -n "$(FILE)" ] || (echo "Usage: make db-restore FILE=backup.dump" && exit 1)
	cat $(FILE) | ssh $(TARGET) 'sudo -u postgres pg_restore -d paperclip --clean --if-exists'

## Check automated backup timer status
db-backup-status:
	ssh $(TARGET) 'systemctl status paperclip-db-backup.timer --no-pager && echo "" && systemctl list-timers paperclip-db-backup.timer --no-pager'

## List remote automated backups (local + off-site)
db-backup-list:
	@echo "=== Local backups ==="
	ssh $(TARGET) 'sudo ls -lh /var/backup/postgresql/ 2>/dev/null || echo "No local backups yet"'
	@echo ""
	@echo "=== Off-site backups (TrueNAS) ==="
	ssh $(TARGET) 'ls -lh /mnt/truenas-nfs/paperclip/db-backups/ 2>/dev/null || echo "No off-site backups yet (NFS may not be mounted)"'

# ─── Secrets (agenix) ─────────────────────────────────────────
.PHONY: rekey edit-secret

## Re-encrypt all secrets with current keys
rekey:
	cd secrets && nix run path:..#agenix -- -r

## Edit a secret (usage: make edit-secret NAME=paperclip-env)
edit-secret:
	@[ -n "$(NAME)" ] || (echo "Usage: make edit-secret NAME=paperclip-env" && exit 1)
	cd secrets && nix run path:..#agenix -- -e $(NAME).age

# ─── SSH ──────────────────────────────────────────────────────
.PHONY: ssh ssh-agent

## SSH as root
ssh:
	ssh $(TARGET)

## SSH as agent user (uses dedicated agent key)
ssh-agent:
	ssh -i ~/.ssh/id_agent_paperclip agent@$(HOST)

# ─── Utilities ────────────────────────────────────────────────
.PHONY: check update update-muninndb

## Check flake evaluates without errors
check:
	nix flake check

## Update flake inputs and pinned dependencies (MuninnDB, etc.)
update: update-muninndb
	nix flake update

## Update MuninnDB binary to the latest GitHub release with Linux binaries.
## Edits modules/services/muninndb.nix in-place; run 'make deploy-nixos' to apply.
update-muninndb:
	@JSON=$$(curl -sf https://api.github.com/repos/scrypster/muninndb/releases) || \
		{ echo "ERROR: Failed to fetch GitHub releases API."; exit 1; }; \
	TAG=$$(printf '%s' "$$JSON" \
		| jq -r '[.[] | select(.assets | map(.name | test("linux_amd64\\.tar\\.gz")) | any)] | first | .tag_name'); \
	URL=$$(printf '%s' "$$JSON" \
		| jq -r '[.[] | select(.assets | map(.name | test("linux_amd64\\.tar\\.gz")) | any)] | first | [.assets[] | select(.name | test("linux_amd64\\.tar\\.gz")) | .browser_download_url] | first'); \
	VERSION=$${TAG#v}; \
	CURRENT=$$(grep 'version = ' modules/services/muninndb.nix | head -1 \
		| sed 's/.*version = "\(.*\)";/\1/'); \
	if [ "$$VERSION" = "$$CURRENT" ]; then \
		echo "MuninnDB already at $$VERSION — nothing to do."; \
		exit 0; \
	fi; \
	echo "Updating MuninnDB: $$CURRENT → $$VERSION"; \
	echo "Fetching Nix hash for $$URL ..."; \
	B32=$$(nix-prefetch-url --type sha256 "$$URL" 2>/dev/null) || \
		{ echo "ERROR: nix-prefetch-url failed. Is the URL reachable?"; exit 1; }; \
	SRI=$$(nix hash convert --hash-algo sha256 --to sri "$$B32"); \
	sed -i "s|version = \"[^\"]*\";|version = \"$$VERSION\";|" modules/services/muninndb.nix; \
	sed -i "s|hash = \"sha256-[^\"]*\";|hash = \"$$SRI\";|" modules/services/muninndb.nix; \
	echo ""; \
	echo "Updated modules/services/muninndb.nix"; \
	echo "  version : $$VERSION"; \
	echo "  hash    : $$SRI"; \
	echo ""; \
	echo "Run 'make deploy-nixos' to apply."

# ─── Help ─────────────────────────────────────────────────────
.PHONY: help

## Show this help
help:
	@echo "Paperclip NixOS Deployment"
	@echo "========================="
	@echo ""
	@echo "First-time setup:"
	@echo "  make generate-host-keys   # Generate + age-encrypt SSH host key"
	@echo "  make edit-secret NAME=paperclip-env  # Create secrets"
	@echo "  make install TARGET=root@<ip>        # Install NixOS (wipes disk!)"
	@echo ""
	@echo "Day-to-day:"
	@echo "  make deploy       # Full rebuild + switch"
	@echo "  make deploy-test  # Test (auto-rollback on disconnect)"
	@echo "  make sync-app     # Fast rsync + migrate (no rebuild)"
	@echo "  make db-migrate   # Apply pending DB migrations only"
	@echo "  make status       # Check services"
	@echo "  make logs         # Follow paperclip logs"
	@echo ""
	@echo "All targets:"
	@grep -B1 -E '^[a-zA-Z_-]+:' Makefile | grep -E '^(##|[a-zA-Z_-]+:)' | sed -n 'N;s/^## \(.*\)\n\([a-zA-Z_-]*\):.*/  make \2\t# \1/p'
