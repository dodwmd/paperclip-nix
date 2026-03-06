{ config, pkgs, ... }:

let
  hardening = import ../lib/hardening.nix;
  dbCfg = import ../lib/db-config.nix;

  # Thresholds
  diskWarningPercent = 85;
  diskCriticalPercent = 95;
  memoryWarningPercent = 85;
  checkIntervalSec = "5min";
  checkBootDelay = "2min";

  # Services to monitor
  criticalServices = [
    "paperclip"
    "postgresql"
    "nginx"
  ];

  postgresqlPkg = config.services.postgresql.package;

  optionalServices = [
    "paperclip-mcp-context7"
  ];

  healthCheck = pkgs.writeShellApplication {
    name = "paperclip-health-check";
    runtimeInputs = [ pkgs.coreutils pkgs.gawk pkgs.systemd pkgs.util-linux postgresqlPkg ];
    text = ''
      WARNINGS=0
      REPORT=""

      add_report() {
        REPORT="''${REPORT}$1"$'\n'
      }

      # --- Service health ---
      CRITICAL_SERVICES=(${builtins.concatStringsSep " " (builtins.map (s: ''"${s}"'') criticalServices)})
      for svc in "''${CRITICAL_SERVICES[@]}"; do
        if ! systemctl is-active --quiet "$svc"; then
          add_report "CRITICAL: Service $svc is not running"
          WARNINGS=$((WARNINGS + 1))
        fi
      done

      OPTIONAL_SERVICES=(${builtins.concatStringsSep " " (builtins.map (s: ''"${s}"'') optionalServices)})
      for svc in "''${OPTIONAL_SERVICES[@]}"; do
        if ! systemctl is-active --quiet "$svc"; then
          add_report "WARNING: Optional service $svc is not running"
        fi
      done

      # --- PostgreSQL connectivity ---
      if ! pg_isready -q -h ${dbCfg.host} -p ${dbCfg.port} -d ${dbCfg.name} -U ${dbCfg.user}; then
        add_report "CRITICAL: PostgreSQL is not accepting connections"
        WARNINGS=$((WARNINGS + 1))
      fi

      # --- Disk space ---
      DISK_USAGE=$(df / --output=pcent | tail -1 | tr -d ' %')
      if [ "$DISK_USAGE" -ge ${toString diskCriticalPercent} ]; then
        add_report "CRITICAL: Disk usage at ''${DISK_USAGE}%"
        WARNINGS=$((WARNINGS + 1))
      elif [ "$DISK_USAGE" -ge ${toString diskWarningPercent} ]; then
        add_report "WARNING: Disk usage at ''${DISK_USAGE}%"
        WARNINGS=$((WARNINGS + 1))
      fi

      # --- Memory ---
      MEM_TOTAL=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
      MEM_AVAIL=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
      MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
      MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
      if [ "$MEM_PCT" -ge ${toString memoryWarningPercent} ]; then
        add_report "WARNING: Memory usage at ''${MEM_PCT}% (''${MEM_AVAIL}kB available)"
        WARNINGS=$((WARNINGS + 1))
      fi

      # --- Summary ---
      if [ "$WARNINGS" -eq 0 ]; then
        echo "OK: All checks passed (disk: ''${DISK_USAGE}%, mem: ''${MEM_PCT}%)"
      else
        # Print report to journald
        printf '%s' "$REPORT"
        # Broadcast to logged-in terminals for immediate visibility
        printf 'paperclip-health-check:\n%s' "$REPORT" | wall 2>/dev/null || true
        # Exit non-zero so systemd marks the unit as failed
        exit 1
      fi
    '';
  };
in
{
  systemd.services.paperclip-health-check = {
    description = "Paperclip System Health Check";
    serviceConfig = hardening.base // {
      Type = "oneshot";
      ExecStart = "${healthCheck}/bin/paperclip-health-check";
      # Run as ephemeral user — health checks only read system state
      DynamicUser = true;
      # Allow reading /proc for memory info and systemctl status
      ProtectProc = "default";
      ProtectHome = true;
      # Override PrivateDevices for wall(1) access to /dev/tty (best-effort, || true)
      PrivateDevices = false;
      # pg_isready needs network, systemctl uses dbus (AF_UNIX from hardening.base)
      SystemCallFilter = [ "@system-service" ];
    };
    # Notify on failure via systemd-journal
    unitConfig = {
      OnFailure = "paperclip-health-notify@%N.service";
    };
  };

  # Failure notification template — logs recent errors and broadcasts to terminals
  systemd.services."paperclip-health-notify@" = {
    description = "Health check failure notification for %i";
    serviceConfig = {
      Type = "oneshot";
      # %i is the systemd instance name (the failed unit)
      ExecStart = "${pkgs.writeShellScript "health-notify" ''
        set -euo pipefail
        UNIT="$1"
        ERRORS=$(${pkgs.systemd}/bin/journalctl -u "$UNIT" --no-pager -n 20 --priority=err 2>&1 || true)
        MSG="HEALTH CHECK FAILED: $UNIT"
        if [ -n "$ERRORS" ]; then
          MSG="$MSG"$'\n'"$ERRORS"
        fi
        printf '%s\n' "$MSG" | ${pkgs.util-linux}/bin/wall 2>/dev/null || true
        printf '%s\n' "$MSG"
      ''} %i";
      # Minimal sandboxing for notification service
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };

  systemd.timers.paperclip-health-check = {
    description = "Periodic Health Check Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = checkBootDelay;
      OnUnitActiveSec = checkIntervalSec;
      Persistent = true;
    };
  };
}
