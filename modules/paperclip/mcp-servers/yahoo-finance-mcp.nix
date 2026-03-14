# Yahoo Finance MCP server — stock prices, financials, options data via yfinance.
# Source: https://github.com/Alex2Yang97/yahoo-finance-mcp
#
# To update: bump rev to latest commit SHA, then update hash:
#   nix-prefetch-url --unpack https://github.com/Alex2Yang97/yahoo-finance-mcp/archive/<rev>.tar.gz
#   nix hash to-sri --type sha256 <base32>
{ pkgs, ... }:

let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;

  src = pkgs.fetchFromGitHub {
    owner = "Alex2Yang97";
    repo = "yahoo-finance-mcp";
    rev = "88ee02382764a91639a402694541360874511653";
    hash = "sha256-yAjzOLAxM4czR4AGZzBe+zRk3YQ+Jv8ATZGVYbgm2S8=";
  };

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    mcp
    yfinance
  ]);

  bin = pkgs.writeShellApplication {
    name = "yahoo-finance-mcp";
    runtimeInputs = [ pythonEnv ];
    text = ''
      exec python ${src}/server.py "$@"
    '';
  };
in
{
  environment.systemPackages = [ bin ];

  systemd.services.paperclip-mcp-yahoo-finance = {
    description = "Yahoo Finance MCP Server for Paperclip";
    after = [ "network.target" ];

    environment = {
      HOME = agentHome;
    };

    serviceConfig = hardening.base // {
      Type = "simple";
      User = serviceUser;
      Group = serviceGroup;
      WorkingDirectory = agentHome;
      ExecStart = "${bin}/bin/yahoo-finance-mcp";
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
