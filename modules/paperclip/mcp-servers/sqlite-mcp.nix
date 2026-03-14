# SQLite MCP server — read/write SQLite databases.
# Source: https://github.com/modelcontextprotocol/servers/tree/main/src/sqlite
# PyPI: mcp-server-sqlite — uses uvx for runtime install.
# Usage: pass db path as argument, e.g. mcp-server-sqlite /path/to/db.sqlite
{ pkgs, ... }:
let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;
  bin = pkgs.writeShellApplication {
    name = "mcp-server-sqlite";
    runtimeInputs = [ pkgs.uv ];
    text = ''exec uvx mcp-server-sqlite "$@"'';
  };
in
{
  environment.systemPackages = [ bin ];
  systemd.services.paperclip-mcp-sqlite = {
    description = "SQLite MCP Server for Paperclip";
    after = [ "network.target" ];
    environment = { HOME = agentHome; UV_TOOL_DIR = "${agentHome}/.local/share/uv/tools"; };
    serviceConfig = hardening.base // {
      Type = "simple"; User = serviceUser; Group = serviceGroup;
      WorkingDirectory = agentHome; ExecStart = "${bin}/bin/mcp-server-sqlite";
      Restart = "on-failure"; RestartSec = mcpRestartDelay;
      ProtectHome = "tmpfs"; BindPaths = [ agentHome ]; ReadWritePaths = [ agentHome ];
      ProtectProc = "invisible"; ProcSubset = "pid";
    };
    unitConfig = { StartLimitBurst = 3; StartLimitIntervalSec = 120; };
  };
}
