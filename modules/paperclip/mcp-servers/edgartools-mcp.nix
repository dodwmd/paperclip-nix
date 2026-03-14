# EdgarTools MCP server — SEC EDGAR filings, XBRL financial statements, 10-K/10-Q/8-K.
# Source: https://github.com/dgunning/edgartools (PyPI: edgartools[ai])
#
# Uses uvx for runtime install due to dependency version constraints that conflict
# with nixpkgs (pyrate-limiter 4.x vs nixpkgs 3.x). First run downloads packages.
# To pin a version: change "edgartools[ai]" to "edgartools[ai]==5.23.2"
#
# Requires: EDGAR_IDENTITY environment variable (name + email for SEC rate limiting).
{ pkgs, ... }:

let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;

  bin = pkgs.writeShellApplication {
    name = "edgartools-mcp";
    runtimeInputs = [ pkgs.uv ];
    text = ''
      exec uvx --from "edgartools[ai]" edgartools-mcp "$@"
    '';
  };
in
{
  environment.systemPackages = [ bin ];

  systemd.services.paperclip-mcp-edgartools = {
    description = "EdgarTools MCP Server for Paperclip";
    after = [ "network.target" ];

    environment = {
      HOME = agentHome;
      UV_TOOL_DIR = "${agentHome}/.local/share/uv/tools";
      EDGAR_IDENTITY = "Michael Dodwell michael@dodwell.us";
    };

    serviceConfig = hardening.base // {
      Type = "simple";
      User = serviceUser;
      Group = serviceGroup;
      WorkingDirectory = agentHome;
      ExecStart = "${bin}/bin/edgartools-mcp";
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
