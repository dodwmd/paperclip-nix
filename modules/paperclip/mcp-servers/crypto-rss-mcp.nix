# Crypto RSS MCP server — aggregates real-time crypto news from multiple RSS feeds.
# Source: https://github.com/kukapay/crypto-rss-mcp
#
# To update: bump rev to latest commit SHA, then update hash:
#   nix-prefetch-url --unpack https://github.com/kukapay/crypto-rss-mcp/archive/<rev>.tar.gz
#   nix hash to-sri --type sha256 <base32>
{ pkgs, ... }:

let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;

  # opml is not yet in nixpkgs — build it from PyPI
  opml = pkgs.python3Packages.buildPythonPackage {
    pname = "opml";
    version = "0.5";
    format = "setuptools";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/source/o/opml/opml-0.5.tar.gz";
      hash = "sha256-2x7vKiUbivM+Lqu2K6+SIAbb2MZsdCkxCQ4zGgNip3A=";
    };
    doCheck = false;
  };

  pkg = pkgs.python3Packages.buildPythonApplication {
    pname = "crypto-rss-mcp";
    version = "0.1.0";
    pyproject = true;

    src = pkgs.fetchFromGitHub {
      owner = "kukapay";
      repo = "crypto-rss-mcp";
      rev = "2cc6a514bfe1c028ddf55193dcfa1073ae2ab3fe";
      hash = "sha256-89HF6JomJsVrg+WoLmpMkg7tFWwEi2zCIaN4ncHenUI=";
    };

    build-system = [ pkgs.python3Packages.hatchling ];

    propagatedBuildInputs = with pkgs.python3Packages; [
      feedparser
      html2text
      mcp
      opml
    ];

    doCheck = false;
  };
in
{
  environment.systemPackages = [ pkg ];

  systemd.services.paperclip-mcp-crypto-rss = {
    description = "Crypto RSS MCP Server for Paperclip";
    after = [ "network.target" ];

    environment = {
      HOME = agentHome;
    };

    serviceConfig = hardening.base // {
      Type = "simple";
      User = serviceUser;
      Group = serviceGroup;
      WorkingDirectory = agentHome;
      ExecStart = "${pkg}/bin/crypto-rss-mcp";
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
