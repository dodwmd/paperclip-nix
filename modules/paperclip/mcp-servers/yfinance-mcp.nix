# YFinance MCP server — Yahoo Finance stock data via FastMCP.
# Source: https://github.com/barvhaim/yfinance-mcp-server
#
# To update: bump rev to latest commit SHA, then update hash:
#   nix-prefetch-url --unpack https://github.com/barvhaim/yfinance-mcp-server/archive/<rev>.tar.gz
#   nix hash to-sri --type sha256 <base32>
{ pkgs, ... }:

let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;

  src = pkgs.fetchFromGitHub {
    owner = "barvhaim";
    repo = "yfinance-mcp-server";
    rev = "5e23e9cf05de133274c0f56d0caa2f37dc969345";
    hash = "sha256-gaUT2ZBvqaSPCWJIJFxNpN8aZamJftvQ8CtZRoaWBhA=";
  };

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    fastmcp
    pandas
    python-dotenv
    yfinance
  ]);

  bin = pkgs.writeShellApplication {
    name = "yfinance-mcp";
    runtimeInputs = [ pythonEnv ];
    text = ''
      exec python ${src}/main.py "$@"
    '';
  };
in
{
  environment.systemPackages = [ bin ];

  systemd.services.paperclip-mcp-yfinance = {
    description = "YFinance MCP Server for Paperclip";
    after = [ "network.target" ];
    environment = { HOME = agentHome; };
    serviceConfig = hardening.base // {
      Type = "simple"; User = serviceUser; Group = serviceGroup;
      WorkingDirectory = agentHome; ExecStart = "${bin}/bin/yfinance-mcp";
      Restart = "on-failure"; RestartSec = mcpRestartDelay;
      ProtectHome = "tmpfs"; BindPaths = [ agentHome ]; ReadWritePaths = [ agentHome ];
      ProtectProc = "invisible"; ProcSubset = "pid";
    };
    unitConfig = { StartLimitBurst = 3; StartLimitIntervalSec = 120; };
  };
}
