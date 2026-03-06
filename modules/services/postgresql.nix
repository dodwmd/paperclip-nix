{ config, lib, pkgs, ... }:

let
  hardening = import ../lib/hardening.nix;
  dbCfg = import ../lib/db-config.nix;

  # Tuned for 8GB RAM NUC (Celeron N5105)
  sharedBuffers = "2GB";       # ~25% of RAM
  effectiveCacheSize = "4GB";  # ~50% of RAM
  workMem = "64MB";
  maintenanceWorkMem = "256MB";
  maxConnections = 50;
in
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    ensureDatabases = [ dbCfg.name ];
    ensureUsers = [
      {
        name = dbCfg.user;
        ensureDBOwnership = true;
      }
    ];
    # Map the "agent" OS user → "paperclip" DB user so agents can connect via
    # Unix socket without a password (peer auth checks OS identity, not a secret).
    # Usage: psql -U paperclip paperclip  (no -h flag — Unix socket only)
    identMap = ''
      agent-map   agent   paperclip
    '';

    # Allow local connections with peer auth + password auth from localhost.
    # The agent-map rule must come before the catch-all "local all all peer" so
    # that "agent" OS user connecting as "paperclip" DB user is matched first.
    authentication = ''
      # TYPE  DATABASE    USER        ADDRESS        METHOD
      local   paperclip   paperclip                  peer map=agent-map
      local   all         all                        peer
      host    all         all         127.0.0.1/32   scram-sha-256
      host    all         all         ::1/128        scram-sha-256
    '';
    settings = {
      password_encryption = "scram-sha-256";
      shared_buffers = sharedBuffers;
      effective_cache_size = effectiveCacheSize;
      work_mem = workMem;
      maintenance_work_mem = maintenanceWorkMem;
      max_connections = maxConnections;

      # Audit logging — track connections and DDL for security visibility
      log_connections = true;
      log_disconnections = true;
      log_statement = "ddl";  # Log schema changes (CREATE, ALTER, DROP)
      log_min_duration_statement = 1000;  # Log queries taking > 1s (performance visibility)

      # Only listen on localhost (never expose to network)
      # Include both IPv4 and IPv6 loopback to match pg_hba.conf entries
      listen_addresses = lib.mkForce "${dbCfg.host},::1";

      # WAL settings for crash safety
      wal_level = "replica";    # Enables point-in-time recovery if needed later
      full_page_writes = true;  # Protect against partial page writes
    };
  };

  # Set the DB user password from agenix secret after PostgreSQL starts.
  # Runs as postgres user via peer auth, reads password from the decrypted secret file.
  systemd.services.postgresql-set-password = {
    description = "Set PostgreSQL ${dbCfg.user} user password from agenix secret";
    after = [ "postgresql.service" "postgresql-setup.service" ];
    requires = [ "postgresql.service" "postgresql-setup.service" ];
    wantedBy = [ "multi-user.target" ];

    # Re-run this service whenever the db-password secret changes (e.g. after rekey)
    restartTriggers = [ config.age.secrets.db-password.file ];

    serviceConfig = hardening.base // {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
      RemainAfterExit = true;
      ProtectHome = true;
      # psql connects via Unix socket — needs access to /run/postgresql
      ReadWritePaths = [ "/run/postgresql" ];
      # No JIT engine — safe to deny W+X memory
      MemoryDenyWriteExecute = true;
      # Override syscall filter for postgres client
      SystemCallFilter = [ "@system-service" ];
      # Wait for PostgreSQL to actually accept connections before running psql
      ExecStartPre = pkgs.writeShellScript "pg-wait-ready" ''
        set -euo pipefail
        for i in $(${pkgs.coreutils}/bin/seq 1 30); do
          if ${config.services.postgresql.package}/bin/pg_isready -q; then
            exit 0
          fi
          echo "Waiting for PostgreSQL to accept connections (attempt $i/30)..."
          ${pkgs.coreutils}/bin/sleep 1
        done
        echo "ERROR: PostgreSQL did not become ready within 30 seconds"
        exit 1
      '';
      ExecStart = pkgs.writeShellScript "pg-set-password" ''
        set -euo pipefail
        PASSWORD=$(${pkgs.coreutils}/bin/cat ${config.age.secrets.db-password.path})
        ESCAPED=$(printf '%s' "$PASSWORD" | ${pkgs.gnused}/bin/sed "s/'/'''/g")
        ${config.services.postgresql.package}/bin/psql -d ${dbCfg.name} \
          -c "ALTER USER ${dbCfg.user} PASSWORD '$ESCAPED';"
      '';
    };
  };
}
