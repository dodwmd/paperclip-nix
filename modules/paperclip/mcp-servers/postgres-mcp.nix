# PostgreSQL MCP server — query and inspect Postgres databases.
# Source: https://github.com/modelcontextprotocol/servers/tree/main/src/postgres
# Usage: pass database URL as first argument, e.g. mcp-server-postgres postgresql://...
{ pkgs, ... }:
let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;
  version = "0.6.2";
  pkgName = "@modelcontextprotocol/server-postgres";
  pkg = pkgs.buildNpmPackage {
    pname = "mcp-server-postgres"; inherit version;
    src = ./postgres;
    npmDepsHash = "sha256-ViQ9kxaJRw+iPCPDCpb92EKSESrc41+auETyj7Qqh28=";
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
    name = "mcp-server-postgres";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''exec node ${pkg}/lib/node_modules/${pkgName}/dist/index.js "$@"'';
  };
in
{
  environment.systemPackages = [ bin ];
  systemd.services.paperclip-mcp-postgres = {
    description = "PostgreSQL MCP Server for Paperclip";
    after = [ "network.target" "postgresql.service" ];
    environment = { NODE_ENV = "production"; HOME = agentHome; };
    serviceConfig = hardening.base // {
      Type = "simple"; User = serviceUser; Group = serviceGroup;
      WorkingDirectory = agentHome; ExecStart = "${bin}/bin/mcp-server-postgres";
      Restart = "on-failure"; RestartSec = mcpRestartDelay;
      ProtectHome = "tmpfs"; BindPaths = [ agentHome ]; ReadWritePaths = [ agentHome ];
      ProtectProc = "invisible"; ProcSubset = "pid";
    };
    unitConfig = { StartLimitBurst = 3; StartLimitIntervalSec = 120; };
  };
}
