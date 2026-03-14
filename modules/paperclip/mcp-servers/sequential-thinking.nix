# Sequential Thinking MCP server — structured reasoning via dynamic thought chains.
# Source: https://www.npmjs.com/package/@modelcontextprotocol/server-sequential-thinking
#
# To update: bump version in sequential-thinking/package.json, regenerate the lock file:
#   cd sequential-thinking && npm install --package-lock-only --ignore-scripts
# Then update npmDepsHash:
#   prefetch-npm-deps sequential-thinking/package-lock.json
{ pkgs, ... }:

let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;

  version = "2025.12.18";
  pkgName = "@modelcontextprotocol/server-sequential-thinking";

  pkg = pkgs.buildNpmPackage {
    pname = "sequential-thinking-mcp";
    inherit version;

    src = ./sequential-thinking;
    npmDepsHash = "sha256-YMxXNJYaDVrisFkR+AuW1MlzEpqgojeglp9DQiPFN14=";
    dontNpmBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/node_modules/${pkgName}
      cp -r node_modules/${pkgName}/* $out/lib/node_modules/${pkgName}/
      cp -r node_modules $out/lib/node_modules/${pkgName}/node_modules
      runHook postInstall
    '';
  };

  bin = pkgs.writeShellApplication {
    name = "sequential-thinking-mcp";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''
      exec node ${pkg}/lib/node_modules/${pkgName}/dist/index.js "$@"
    '';
  };
in
{
  environment.systemPackages = [ bin ];

  systemd.services.paperclip-mcp-sequential-thinking = {
    description = "Sequential Thinking MCP Server for Paperclip";
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
      ExecStart = "${bin}/bin/sequential-thinking-mcp";
      Restart = "on-failure";
      RestartSec = mcpRestartDelay;
      ProtectHome = "tmpfs";
      BindPaths = [ agentHome ];
      ReadWritePaths = [ agentHome ];
      ProtectProc = "invisible";
      ProcSubset = "pid";
    };

    unitConfig = {
      StartLimitBurst = 3;
      StartLimitIntervalSec = 120;
    };
  };
}
