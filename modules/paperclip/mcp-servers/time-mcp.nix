# Time MCP server — current time and timezone conversions.
# Source: https://github.com/modelcontextprotocol/servers/tree/main/src/time
# PyPI: mcp-server-time — uses uvx for runtime install.
{ pkgs, ... }:
let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;
  bin = pkgs.writeShellApplication {
    name = "mcp-server-time";
    runtimeInputs = [ pkgs.uv ];
    text = ''exec uvx mcp-server-time "$@"'';
  };
in
{
  environment.systemPackages = [ bin ];
  systemd.services.paperclip-mcp-time = {
    description = "Time MCP Server for Paperclip";
    after = [ "network.target" ];
    environment = { HOME = agentHome; UV_TOOL_DIR = "${agentHome}/.local/share/uv/tools"; };
    serviceConfig = hardening.base // {
      Type = "simple"; User = serviceUser; Group = serviceGroup;
      WorkingDirectory = agentHome; ExecStart = "${bin}/bin/mcp-server-time";
      Restart = "on-failure"; RestartSec = mcpRestartDelay;
      ProtectHome = "tmpfs"; BindPaths = [ agentHome ]; ReadWritePaths = [ agentHome ];
      ProtectProc = "invisible"; ProcSubset = "pid";
    };
    unitConfig = { StartLimitBurst = 3; StartLimitIntervalSec = 120; };
  };
}
