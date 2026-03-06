{ config, pkgs, lib, ... }:

let
  hardening = import ../lib/hardening.nix;

  # Pin to latest release that has pre-built binaries.
  # To update: find the new tag at https://github.com/scrypster/muninndb/releases,
  # then run: nix-prefetch-url --type sha256 <tarball-url>
  # and convert: nix hash convert --hash-algo sha256 --to sri <base32-hash>
  version = "0.3.6-alpha";

  serviceUser = "agent";
  serviceGroup = "users";
  agentHome = "/home/${serviceUser}";
  dataDir = "${agentHome}/.muninn/data";
  mcpPort = 8750;
  restartDelay = "10s";

  muninnPkg = pkgs.stdenv.mkDerivation {
    pname = "muninndb";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/scrypster/muninndb/releases/download/v${version}/muninn_v${version}_linux_amd64.tar.gz";
      hash = "sha256-G5QODM9ltzlnEta08agpx5erS0LB/I+wZ3XcQsuaAeA=";
    };

    # Tarball unpacks to a flat directory — binary is named "muninn"
    sourceRoot = ".";

    # The binary is CGO-linked against glibc. autoPatchelfHook rewrites the
    # ELF interpreter and RPATH to use Nix store paths so it runs on NixOS.
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];  # libgcc_s / libstdc++

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      cp muninn $out/bin/
      chmod +x $out/bin/muninn
      runHook postInstall
    '';

    meta.platforms = [ "x86_64-linux" ];
  };

  # MCP config for Claude Code running as agent user.
  # Uses HTTP transport to the running MuninnDB service (not spawned as subprocess).
  # Optional: if ~/.muninn/mcp.token exists, add a "headers" block with Authorization.
  mcpJsonFile = pkgs.writeText "mcp.json" (builtins.toJSON {
    mcpServers = {
      muninndb = {
        type = "http";
        url = "http://127.0.0.1:${toString mcpPort}/mcp";
      };
    };
  });
in
{
  # MuninnDB — vector memory database with MCP interface (port 8750)
  # Ports: 8474 binary, 8475 REST, 8476 Web UI, 8477 gRPC, 8750 MCP
  # All ports are localhost-only; expose via nginx if external access is needed.
  systemd.services.muninndb = {
    description = "MuninnDB Memory Database";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      MUNINNDB_DATA = dataDir;
      HOME = agentHome;
      # Embeddings: bundled local model is used by default (MUNINN_LOCAL_EMBED=1).
      # Override with MUNINN_OPENAI_KEY / MUNINN_OLLAMA_URL if needed.
    };

    serviceConfig = hardening.base // {
      Type = "simple";
      User = serviceUser;
      Group = serviceGroup;
      WorkingDirectory = agentHome;

      # Non-interactive init on first run (--no-start: don't auto-start, we manage that;
      # --no-token: open MCP, we deploy .mcp.json via Nix; --yes: skip prompts).
      # The leading "-" makes systemd ignore a non-zero exit (e.g. already initialised).
      ExecStartPre = [ "-${muninnPkg}/bin/muninn init --yes --no-token --no-start" ];
      ExecStart = "${muninnPkg}/bin/muninn start";

      Restart = "on-failure";
      RestartSec = restartDelay;

      # Home overlay — bind agent home so muninn can write to ~/.muninn/data
      ProtectHome = "tmpfs";
      BindPaths = [ agentHome ];
      ReadWritePaths = [ agentHome ];

      ProtectProc = "invisible";
      ProcSubset = "pid";
      # Go binaries don't use JIT — MemoryDenyWriteExecute=true is safe to add
      # here if desired, but omit for compatibility with race detector builds.
    };

    unitConfig = {
      StartLimitBurst = 3;
      StartLimitIntervalSec = 120;
    };
  };

  # Create data directory and deploy MCP config for Claude Code (agent user).
  # C+ copies the Nix-managed file on every activation, keeping it in sync with
  # this derivation. Manual edits to .mcp.json will be overwritten at next boot.
  systemd.tmpfiles.rules = [
    # systemd-tmpfiles does not create parent directories automatically,
    # so both levels must be listed explicitly.
    "d ${agentHome}/.muninn 0700 ${serviceUser} ${serviceGroup} -"
    "d ${dataDir}           0700 ${serviceUser} ${serviceGroup} -"
    "C+ ${agentHome}/.mcp.json 0644 ${serviceUser} ${serviceGroup} - ${mcpJsonFile}"
  ];

  # Allow agent to manage the muninndb service without a password
  security.sudo.extraRules = lib.mkAfter [
    {
      users = [ serviceUser ];
      commands = [
        {
          command = "/run/current-system/sw/bin/systemctl start muninndb";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl restart muninndb";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl stop muninndb";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
