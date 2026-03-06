{ config, pkgs, ... }:

let
  hardening = import ../lib/hardening.nix;
  dbCfg = import ../lib/db-config.nix;

  backupDir = "/var/backup/postgresql";
  retentionDays = 14;
  backupBootDelay = "10min";
  backupJitter = "30min";
in
{
  # Daily automated PostgreSQL backup with rotation
  systemd.services.paperclip-db-backup = {
    description = "Paperclip PostgreSQL Daily Backup";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    # Trigger off-site sync after successful local backup
    onSuccess = [ "paperclip-db-backup-offsite.service" ];

    serviceConfig = hardening.base // {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
      ProtectHome = true;
      ReadWritePaths = [ backupDir ];
      # pg_dump connects via Unix socket — no extra capabilities needed
      # No JIT engine — safe to deny W+X memory
      MemoryDenyWriteExecute = true;
      # Use base syscall filter but exclude ~@resources since pg_dump needs shmget/mmap
      SystemCallFilter = [ "@system-service" "~@privileged" ];
      ExecStart = pkgs.writeShellScript "paperclip-db-backup" ''
        set -euo pipefail
        TIMESTAMP=$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)
        BACKUP_FILE="${backupDir}/${dbCfg.name}-''${TIMESTAMP}.dump"

        # Dump in custom format (supports parallel restore, selective table restore, built-in compression)
        ${config.services.postgresql.package}/bin/pg_dump --format=custom ${dbCfg.name} > "$BACKUP_FILE"
        ${pkgs.coreutils}/bin/chmod 600 "$BACKUP_FILE"

        # Verify the dump is non-empty before pruning old backups
        DUMP_SIZE=$(${pkgs.coreutils}/bin/stat --format='%s' "$BACKUP_FILE")
        if [ "$DUMP_SIZE" -lt 1024 ]; then
          echo "ERROR: Backup file is suspiciously small (''${DUMP_SIZE} bytes), skipping prune"
          exit 1
        fi

        # Prune backups older than ${toString retentionDays} days
        ${pkgs.findutils}/bin/find "${backupDir}" -name "${dbCfg.name}-*.dump" -mtime +${toString retentionDays} -delete

        echo "Backup complete: $BACKUP_FILE (''${DUMP_SIZE} bytes)"
      '';
    };
  };

  # Run daily at 02:00
  systemd.timers.paperclip-db-backup = {
    description = "Daily Paperclip PostgreSQL Backup Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 02:00:00";
      OnBootSec = backupBootDelay;
      Persistent = true;
      RandomizedDelaySec = backupJitter;
    };
  };

  # Create backup directory with correct permissions
  systemd.tmpfiles.rules = [
    "d ${backupDir} 0700 postgres postgres -"
  ];
}
