{ config, pkgs, ... }:

let
  hardening = import ../lib/hardening.nix;
  dbCfg = import ../lib/db-config.nix;

  backupDir = "/var/backup/postgresql";
  backupBootDelay = "10min";
  backupJitter = "30min";

  # GFS (Grandfather-Father-Son) retention policy:
  #   Daily (son)        — keep last 7 days
  #   Weekly (father)    — keep one per week (Sundays) for 4 weeks
  #   Monthly (grandfather) — keep one per month (1st) for 6 months
  # Safety: hard cap at maxTotalMB to prevent disk fill regardless of policy.
  keepDailyDays = 7;
  keepWeeklyWeeks = 4;
  keepMonthlyMonths = 6;
  maxTotalMB = 500;

  gfsRotateScript = pkgs.writeShellScript "paperclip-db-backup" ''
    set -euo pipefail

    DATE=${pkgs.coreutils}/bin/date
    FIND=${pkgs.findutils}/bin/find
    STAT=${pkgs.coreutils}/bin/stat
    SORT=${pkgs.coreutils}/bin/sort
    HEAD=${pkgs.coreutils}/bin/head
    TAIL=${pkgs.coreutils}/bin/tail
    AWK=${pkgs.gawk}/bin/awk
    BASENAME=${pkgs.coreutils}/bin/basename
    RM=${pkgs.coreutils}/bin/rm
    DU=${pkgs.coreutils}/bin/du

    BACKUP_DIR="${backupDir}"
    DB_NAME="${dbCfg.name}"

    TIMESTAMP=$($DATE +%Y%m%d-%H%M%S)
    BACKUP_FILE="''${BACKUP_DIR}/''${DB_NAME}-''${TIMESTAMP}.dump"

    # --- Create backup ---
    ${config.services.postgresql.package}/bin/pg_dump --format=custom "$DB_NAME" > "$BACKUP_FILE"
    ${pkgs.coreutils}/bin/chmod 600 "$BACKUP_FILE"

    DUMP_SIZE=$($STAT --format='%s' "$BACKUP_FILE")
    if [ "$DUMP_SIZE" -lt 1024 ]; then
      echo "ERROR: Backup file is suspiciously small (''${DUMP_SIZE} bytes), skipping rotation"
      exit 1
    fi

    echo "Backup complete: $BACKUP_FILE (''${DUMP_SIZE} bytes)"

    # --- GFS rotation ---
    # Collect all backup files sorted oldest-first
    mapfile -t ALL_BACKUPS < <($FIND "$BACKUP_DIR" -maxdepth 1 -name "''${DB_NAME}-*.dump" -printf '%T@ %p\n' | $SORT -n | $AWK '{print $2}')

    if [ ''${#ALL_BACKUPS[@]} -le 1 ]; then
      echo "Only one backup exists, nothing to rotate"
      exit 0
    fi

    # Build a set of backups to KEEP based on GFS tiers
    declare -A KEEP

    # Always keep the backup we just created
    KEEP["$BACKUP_FILE"]=1

    NOW=$($DATE +%s)

    # Tier 1 (Son): keep all backups from the last ${toString keepDailyDays} days
    DAILY_CUTOFF=$((NOW - ${toString keepDailyDays} * 86400))
    for f in "''${ALL_BACKUPS[@]}"; do
      MTIME=$($STAT --format='%Y' "$f")
      if [ "$MTIME" -ge "$DAILY_CUTOFF" ]; then
        KEEP["$f"]=1
      fi
    done

    # Tier 2 (Father): keep the newest backup per ISO week for the last ${toString keepWeeklyWeeks} weeks
    WEEKLY_CUTOFF=$((NOW - ${toString keepWeeklyWeeks} * 7 * 86400))
    declare -A WEEK_BEST
    for f in "''${ALL_BACKUPS[@]}"; do
      MTIME=$($STAT --format='%Y' "$f")
      if [ "$MTIME" -ge "$WEEKLY_CUTOFF" ]; then
        WEEK_KEY=$($DATE -d "@$MTIME" +%G-W%V)
        # Keep the newest backup for each week (array is oldest-first, so last write wins)
        WEEK_BEST["$WEEK_KEY"]="$f"
      fi
    done
    for f in "''${WEEK_BEST[@]}"; do
      KEEP["$f"]=1
    done

    # Tier 3 (Grandfather): keep the newest backup per month for the last ${toString keepMonthlyMonths} months
    MONTHLY_CUTOFF=$((NOW - ${toString keepMonthlyMonths} * 31 * 86400))
    declare -A MONTH_BEST
    for f in "''${ALL_BACKUPS[@]}"; do
      MTIME=$($STAT --format='%Y' "$f")
      if [ "$MTIME" -ge "$MONTHLY_CUTOFF" ]; then
        MONTH_KEY=$($DATE -d "@$MTIME" +%Y-%m)
        MONTH_BEST["$MONTH_KEY"]="$f"
      fi
    done
    for f in "''${MONTH_BEST[@]}"; do
      KEEP["$f"]=1
    done

    # Delete backups not in the KEEP set
    DELETED=0
    for f in "''${ALL_BACKUPS[@]}"; do
      if [ -z "''${KEEP[$f]+x}" ]; then
        echo "Rotating: $($BASENAME "$f")"
        $RM -f "$f"
        DELETED=$((DELETED + 1))
      fi
    done

    echo "GFS rotation: kept ''${#KEEP[@]} backups, removed $DELETED"

    # --- Safety cap: enforce max total size ---
    TOTAL_KB=$($DU -sk "$BACKUP_DIR" | $AWK '{print $1}')
    MAX_KB=$((${toString maxTotalMB} * 1024))
    if [ "$TOTAL_KB" -gt "$MAX_KB" ]; then
      echo "WARNING: Backup dir is ''${TOTAL_KB}kB (cap: ''${MAX_KB}kB), removing oldest backups"
      mapfile -t SIZE_SORTED < <($FIND "$BACKUP_DIR" -maxdepth 1 -name "''${DB_NAME}-*.dump" -printf '%T@ %p\n' | $SORT -n | $AWK '{print $2}')
      for f in "''${SIZE_SORTED[@]}"; do
        # Never delete the latest backup
        if [ "$f" = "$BACKUP_FILE" ]; then
          continue
        fi
        echo "Size cap: removing $($BASENAME "$f")"
        $RM -f "$f"
        TOTAL_KB=$($DU -sk "$BACKUP_DIR" | $AWK '{print $1}')
        if [ "$TOTAL_KB" -le "$MAX_KB" ]; then
          break
        fi
      done
      echo "After size cap enforcement: ''${TOTAL_KB}kB"
    fi
  '';
in
{
  # Daily automated PostgreSQL backup with GFS rotation
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
      ExecStart = gfsRotateScript;
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
