{ config, pkgs, ... }:

let
  hardening = import ../lib/hardening.nix;
  dbCfg = import ../lib/db-config.nix;

  localBackupDir = "/var/backup/postgresql";
  nfsMountPoint = "/mnt/truenas-nfs";
  remoteBackupDir = "${nfsMountPoint}/paperclip/db-backups";
  truenasHost = "192.168.1.6";
  nfsExport = "/mnt/tank/nfs";
  remoteRetentionDays = 30;
  nfsTimeoutDs = 30;        # deciseconds (timeo=30 -> 3s)
  nfsRetrans = 3;
  nfsIdleTimeoutSec = 60;
in
{
  # NFS client support
  services.rpcbind.enable = true;

  # Mount TrueNAS NFS share
  fileSystems."${nfsMountPoint}" = {
    device = "${truenasHost}:${nfsExport}";
    fsType = "nfs";
    options = [
      "soft"                                                  # Return errors instead of hanging
      "timeo=${toString nfsTimeoutDs}"                        # Timeout in deciseconds
      "retrans=${toString nfsRetrans}"                        # Retries before giving up
      "nofail"                                                # Don't block boot if unreachable
      "noexec"                                                # Prevent execution from NFS mount
      "nosuid"                                                # Ignore setuid bits on NFS mount
      "nodev"                                                 # No device files on NFS mount
      "x-systemd.automount"                                   # Mount on first access
      "x-systemd.idle-timeout=${toString nfsIdleTimeoutSec}"  # Unmount after idle
    ];
  };

  # Off-site backup: copy local PostgreSQL backups to TrueNAS after each backup run
  systemd.services.paperclip-db-backup-offsite = {
    description = "Paperclip PostgreSQL Off-Site Backup to TrueNAS";
    # Only ordering dependency on paperclip-db-backup — not Requires/BindsTo.
    # The backup is Type=oneshot (no RemainAfterExit), so it goes inactive after
    # completion. A Requires= dependency would cause systemd to stop this service
    # when the oneshot becomes inactive. The onSuccess trigger in postgresql-backup.nix
    # already ensures correct invocation ordering.
    after = [ "paperclip-db-backup.service" "mnt-truenas\\x2dnfs.automount" ];

    serviceConfig = hardening.base // {
      Type = "oneshot";
      User = "root"; # Needs root to access NFS mount and postgres-owned backups
      # Root service needs DAC_READ_SEARCH to read postgres-owned backups,
      # DAC_OVERRIDE to create directories on NFS, CHOWN for ownership on NFS,
      # CAP_NET_RAW for ping reachability check (NoNewPrivileges blocks setuid ping)
      CapabilityBoundingSet = [ "CAP_DAC_READ_SEARCH" "CAP_DAC_OVERRIDE" "CAP_CHOWN" "CAP_NET_RAW" ];
      ProtectHome = true;
      MemoryDenyWriteExecute = true;
      ReadWritePaths = [ nfsMountPoint localBackupDir ];
      # Override syscall filter — rsync and NFS operations need broader set
      SystemCallFilter = [ "@system-service" "~@privileged" ];

      ExecStart = pkgs.writeShellScript "paperclip-db-backup-offsite" ''
        set -euo pipefail

        # Check if NFS is reachable before attempting mount/sync
        if ! ${pkgs.iputils}/bin/ping -c 1 -W 3 ${truenasHost} >/dev/null 2>&1; then
          echo "WARNING: TrueNAS (${truenasHost}) unreachable — skipping off-site backup"
          echo "Local backups in ${localBackupDir} are still intact"
          exit 0
        fi

        # Ensure remote backup directory exists
        if ! ${pkgs.coreutils}/bin/mkdir -p "${remoteBackupDir}" 2>/dev/null; then
          echo "WARNING: Cannot create ${remoteBackupDir} — NFS mount may have failed"
          echo "Local backups in ${localBackupDir} are still intact"
          exit 0
        fi

        # Rsync local backups to TrueNAS (only copies new/changed files)
        ${pkgs.rsync}/bin/rsync -a --ignore-existing \
          "${localBackupDir}/" \
          "${remoteBackupDir}/"

        # Prune remote backups older than ${toString remoteRetentionDays} days
        ${pkgs.findutils}/bin/find "${remoteBackupDir}" -name "${dbCfg.name}-*.dump" -mtime +${toString remoteRetentionDays} -delete

        echo "Off-site backup sync complete to ${remoteBackupDir}"
      '';
    };
  };

  # No separate timer — off-site sync is triggered by onSuccess in postgresql-backup.nix
  # This ensures it always runs after a successful local backup, not on an independent schedule.
}
