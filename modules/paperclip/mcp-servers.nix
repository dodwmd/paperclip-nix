{ config, pkgs, ... }:

let
  hardening = import ../lib/hardening.nix;

  # Context7 MCP server — provides documentation context for AI agents
  # Pin version for reproducibility. Update by checking:
  #   npm view @upstash/context7-mcp version
  context7Version = "2.1.3";

  serviceUser = "agent";
  serviceGroup = "users";
  agentHome = "/home/${serviceUser}";
  mcpRestartDelay = "15s";

  # Pre-built Context7 package (avoids runtime npx fetch)
  context7Pkg = pkgs.buildNpmPackage {
    pname = "context7-mcp";
    version = context7Version;

    src = ./context7-mcp;

    npmDepsHash = "sha256-oRxWUr6fdFLC+uMFNYTgypglV4JjTK2CcLVgnslYahk=";
    dontNpmBuild = true;

    # The package doesn't need building, just installing deps
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/node_modules/@upstash/context7-mcp
      cp -r node_modules/@upstash/context7-mcp/* $out/lib/node_modules/@upstash/context7-mcp/
      cp -r node_modules $out/lib/node_modules/@upstash/context7-mcp/node_modules
      runHook postInstall
    '';
  };

  context7Bin = pkgs.writeShellApplication {
    name = "context7-mcp";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''
      exec node ${context7Pkg}/lib/node_modules/@upstash/context7-mcp/dist/index.js "$@"
    '';
  };
in
{
  # Context7 MCP server (stdio mode, started on-demand by paperclip — not auto-started)
  systemd.services.paperclip-mcp-context7 = {
    description = "Context7 MCP Server for Paperclip";
    after = [ "network.target" ];

    environment = {
      NODE_ENV = "production";
      HOME = agentHome;
    };

    serviceConfig = hardening.base // {
      Type = "simple";
      User = serviceUser;
      Group = serviceGroup;
      WorkingDirectory = agentHome;
      ExecStart = "${context7Bin}/bin/context7-mcp";
      Restart = "on-failure";
      RestartSec = mcpRestartDelay;

      # Home overlay — bind agent home for npm cache
      ProtectHome = "tmpfs";
      BindPaths = [ agentHome ];
      ReadWritePaths = [ agentHome ];

      ProtectProc = "invisible";
      ProcSubset = "pid";
    };

    # Rate limit restarts — belongs in [Unit], not [Service]
    unitConfig = {
      StartLimitBurst = 3;
      StartLimitIntervalSec = 120;
    };
  };

  # MCP server configuration for paperclip
  # Place this config so paperclip knows about available MCP servers
  environment.etc."paperclip/mcp-servers.json".text = builtins.toJSON {
    mcpServers = {
      context7 = {
        command = "${context7Bin}/bin/context7-mcp";
        args = [];
        description = "Context7 — resolve library documentation and code examples";
      };
    };
  };
}
