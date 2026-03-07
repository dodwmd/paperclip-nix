{ config, pkgs, ... }:

let
  hardening = import ../lib/hardening.nix;
  dbCfg = import ../lib/db-config.nix;

  serviceUser = "agent";
  serviceGroup = "users";
  paperclipDir = "/home/${serviceUser}/paperclip";
  paperclipHome = "/home/${serviceUser}/.paperclip";
  claudeDir = "/home/${serviceUser}/.claude";
  claudeConfig = "/home/${serviceUser}/.claude.json";
  paperclipHost = "127.0.0.1";
  paperclipPort = "3100";
  restartDelay = "10s";
  runtimeEnvDir = "/run/paperclip";

  paperclipPrepare = pkgs.writeShellApplication {
    name = "paperclip-prepare";
    runtimeInputs = [ pkgs.coreutils pkgs.git pkgs.nodejs_22 pkgs.nodePackages.pnpm ];
    text = builtins.readFile ./scripts/paperclip-prepare.sh;
  };
in
{
  # Paperclip control plane systemd service
  systemd.services.paperclip = {
    description = "Paperclip AI Agent Control Plane";
    after = [ "network.target" "postgresql.service" "postgresql-set-password.service" ];
    requires = [ "postgresql.service" "postgresql-set-password.service" ];
    wantedBy = [ "multi-user.target" ];

    # Expose all system packages to child processes (agents, git, node, claude, etc.)
    # Using systemPackages means any tool added to the system is automatically available
    # to agents without needing to update this list.
    path = config.environment.systemPackages;

    environment = {
      NODE_ENV = "production";
      HOST = paperclipHost; # nginx handles external access
      PORT = paperclipPort;
      PNPM_HOME = "${paperclipHome}/pnpm";
      SERVE_UI = "true";
      PAPERCLIP_HOME = paperclipHome;
      PAPERCLIP_INSTANCE_ID = "default";
      PAPERCLIP_DEPLOYMENT_MODE = "local_trusted";
      PAPERCLIP_MIGRATION_AUTO_APPLY = "true"; # apply pending migrations on startup
      PAPERCLIP_MIGRATION_PROMPT = "never";    # safety net: don't hang on interactive prompt if AUTO_APPLY is unset
      # DATABASE_URL built at runtime from db-password secret (see ExecStartPre)
    };

    serviceConfig = hardening.base // {
      Type = "simple";
      User = serviceUser;
      Group = serviceGroup;
      WorkingDirectory = paperclipDir;
      RuntimeDirectory = "paperclip";
      RuntimeDirectoryMode = "0700";
      ExecStartPre = [
        # Build DATABASE_URL from the db-password secret
        # URL-encode the password to handle special characters (e.g. @, /, %)
        "+${pkgs.writeShellScript "paperclip-db-env" ''
          set -euo pipefail
          DB_PASS=$(${pkgs.coreutils}/bin/tr -d '\n' < ${config.age.secrets.db-password.path})
          # URL-encode special characters in the password (jq @uri — avoids python3 in closure)
          ENCODED_PASS=$(printf '%s' "$DB_PASS" | ${pkgs.jq}/bin/jq -sRr '@uri')
          printf 'DATABASE_URL=postgresql://${dbCfg.user}:%s@${dbCfg.host}:${dbCfg.port}/${dbCfg.name}\n' "$ENCODED_PASS" > ${runtimeEnvDir}/db-env
          ${pkgs.coreutils}/bin/chown ${serviceUser}:${serviceGroup} ${runtimeEnvDir}/db-env
          ${pkgs.coreutils}/bin/chmod 0400 ${runtimeEnvDir}/db-env
        ''}"
        # Conditional pnpm install + build
        "${paperclipPrepare}/bin/paperclip-prepare ${paperclipDir}"
      ];
      ExecStart = "${pkgs.nodejs_22}/bin/node server/dist/index.js";
      Restart = "on-failure";
      RestartSec = restartDelay;

      # Load secrets — db-env built at runtime by ExecStartPre, paperclip-env for API keys etc.
      # Note: systemd loads EnvironmentFile for each Exec* process independently. Since
      # ExecStartPre creates db-env before ExecStart spawns, db-env will exist when the
      # main process loads it. The "-" prefix makes it non-fatal on first activation
      # before the RuntimeDirectory is populated.
      EnvironmentFile = [
        "-${runtimeEnvDir}/db-env"
        config.age.secrets.paperclip-env.path
      ];

      # Home overlay — bind only required paths
      ProtectHome = "tmpfs";
      BindPaths = [
        paperclipDir
        paperclipHome
        claudeDir     # claude session state, history, cache
        claudeConfig  # claude main config + auth (~/.claude.json)
      ];
      ReadWritePaths = [
        paperclipDir
        paperclipHome
        claudeDir
        claudeConfig
      ];

      # Additional sandboxing for Node.js process
      ProtectProc = "invisible";
      ProcSubset = "pid";
      # Note: MemoryDenyWriteExecute=true is incompatible with Node.js V8 JIT
      # Note: PrivateDevices=true is already set via hardening.base
    };

    # Rate limit restarts (max 5 in 60s) — belongs in [Unit], not [Service]
    unitConfig = {
      StartLimitBurst = 5;
      StartLimitIntervalSec = 60;
    };
  };

  # Create required directories declaratively
  systemd.tmpfiles.rules = [
    "d ${paperclipDir} 0750 ${serviceUser} ${serviceGroup} -"
    "d ${paperclipHome} 0700 ${serviceUser} ${serviceGroup} -"
    "d ${paperclipHome}/instances/default 0700 ${serviceUser} ${serviceGroup} -"
    "d ${paperclipHome}/instances/default/logs 0700 ${serviceUser} ${serviceGroup} -"
    "d ${paperclipHome}/instances/default/secrets 0700 ${serviceUser} ${serviceGroup} -"
    "d ${paperclipHome}/pnpm 0700 ${serviceUser} ${serviceGroup} -"
    "d ${claudeDir} 0700 ${serviceUser} ${serviceGroup} -"
    "f ${claudeConfig} 0600 ${serviceUser} ${serviceGroup} -"
  ];
}
