# Paperclip NixOS Deployment

NixOS configuration for deploying Paperclip to `zoe.home.dodwell.us` — an Intel NUC (Celeron N5105, 8GB RAM, 128GB NVMe).

## Quick Start

### 1. Generate host keys (run once)

```bash
cd nix
make generate-host-keys
```

This pre-generates the NUC's SSH host key pair. The private key is age-encrypted
(with your user key only — bootstrap secret) and committed. The public key is
committed as plaintext. At install time, the private key is decrypted locally and
injected into the NUC via `--extra-files`, so agenix secrets work from first boot.

### 2. Create secrets

```bash
# Set the database password (used to build DATABASE_URL at runtime)
make edit-secret NAME=db-password

# Create the paperclip env file (API keys, etc.)
# NOTE: Do NOT add DATABASE_URL here — it is built automatically from db-password
make edit-secret NAME=paperclip-env

make edit-secret NAME=github-pat
```

### 3. Install NixOS on the NUC

```bash
# Boot the NUC from a NixOS installer USB, then:
make install TARGET=root@<nuc-ip>
```

This runs nixos-anywhere which:
- Partitions the disk (disko)
- Installs NixOS with the paperclip config
- Injects the pre-generated host key into `/etc/ssh/`
- All agenix secrets are decryptable from first boot

### 4. Deploy updates

```bash
make deploy          # Full rebuild + switch
make deploy-test     # Test (auto-rollback on disconnect)
make sync-app        # Fast: just rsync the app code
```

## Structure

```
nix/
├── flake.nix                          # Flake definition
├── Makefile                           # Deployment commands
├── hosts/paperclip/
│   ├── default.nix                    # Host config
│   ├── hardware-configuration.nix     # NUC hardware
│   ├── disk-config.nix                # Disko partitions
│   ├── networking.nix                 # Firewall (SSH), fail2ban
│   └── users.nix                      # dodwmd, agent, root
├── modules/
│   ├── core/                          # Boot, nix settings, locale
│   ├── lib/
│   │   ├── hardening.nix              # Shared systemd hardening options
│   │   └── db-config.nix              # Shared database constants (name, user, host, port)
│   ├── services/                      # SSH, tmux, PostgreSQL, nginx, backups, monitoring
│   ├── paperclip/
│   │   ├── packages/                  # Full-stack dev tooling (core, nodejs, python, etc.)
│   │   ├── service.nix                # Paperclip systemd service
│   │   ├── mcp-servers.nix            # Context7 MCP server
│   │   ├── context7-mcp/              # Pinned npm package for Nix build
│   │   └── scripts/                   # Helper scripts (paperclip-prepare.sh)
│   └── secrets.nix                    # Agenix secret declarations
└── secrets/
    ├── secrets.nix                    # Age encryption keys
    ├── ssh_host_ed25519_key.age       # Private host key (age-encrypted, committed)
    ├── db-password.age                # PostgreSQL password (age-encrypted)
    ├── paperclip-env.age              # App env vars (age-encrypted)
    ├── github-pat.age                 # GitHub PAT (age-encrypted)
    └── host-keys/
        └── ssh_host_ed25519_key.pub   # Public host key (plaintext, committed)
```

## Host Key Flow

```
make generate-host-keys
    ├── secrets/host-keys/ssh_host_ed25519_key.pub  (plaintext, committed)
    │     └── Used by secrets/secrets.nix to encrypt app secrets for the host
    └── secrets/ssh_host_ed25519_key.age  (age-encrypted with USER key only, committed)
          └── Bootstrap secret: can't encrypt a key with itself

make install
    └── Decrypts .age file locally using your SSH key (~/.ssh/id_ed25519)
        └── nixos-anywhere --extra-files ...
            └── Injects private key to /etc/ssh/ssh_host_ed25519_key on NUC
                └── agenix uses this key to decrypt all app secrets on first boot
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| nginx | 80 | Reverse proxy (external access) |
| Paperclip | 3100 | API + UI (localhost only, behind nginx) |
| PostgreSQL | 5432 | Database (local only) |
| Context7 MCP | stdio | Documentation context for agents |
| SSH | 22 | Remote access |

TLS is handled externally by the k3s cluster, which proxies HTTPS to `http://zoe.home.dodwell.us/`.

## Backups

- **Local**: Daily `pg_dump --format=custom` at 02:00 (±30min jitter), 14-day retention in `/var/backup/postgresql/`
- **Off-site**: Synced to TrueNAS (`192.168.1.6:/mnt/tank/nfs/paperclip/db-backups/`), 30-day retention

## SSH Access

```bash
make ssh             # SSH as root (emergency/provisioning)
make ssh-agent       # SSH as agent user (uses ~/.ssh/id_agent_paperclip)
```

## Useful Commands

```bash
make status          # Check all services
make logs            # Follow paperclip logs
make logs-mcp        # Follow MCP server logs
make logs-nginx      # Follow nginx logs
make db-shell          # psql into paperclip DB
make db-backup         # Dump DB to local .dump file (custom format)
make db-backup-status  # Check automated backup timer status
make db-backup-list    # List local + off-site backups
make db-restore FILE=backup.dump  # Restore from .dump file
make help              # Show all targets
```
