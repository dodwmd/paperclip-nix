# Free Crypto News MCP server — real-time crypto news via 200+ sources, no API key required.
# Source: https://www.npmjs.com/package/@nirholas/free-crypto-news-mcp
# GitHub: https://github.com/nirholas/free-crypto-news
#
# To update: bump version in free-crypto-news/package.json, regenerate the lock file:
#   cd free-crypto-news && npm install --package-lock-only --ignore-scripts
# Then update npmDepsHash:
#   nix run nixpkgs#prefetch-npm-deps -- free-crypto-news/package-lock.json
{ pkgs, ... }:

let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;

  version = "1.0.3";
  pkgName = "@nirholas/free-crypto-news-mcp";

  pkg = pkgs.buildNpmPackage {
    pname = "free-crypto-news-mcp";
    inherit version;

    src = ./free-crypto-news;
    npmDepsHash = "sha256-vTyCGaOI2FxXujXE0v0PYQ2G0HzllV/Iks5WqVvCF/w=";
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
    name = "free-crypto-news-mcp";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''
      exec node ${pkg}/lib/node_modules/${pkgName}/index.js "$@"
    '';
  };
in
{
  environment.systemPackages = [ bin ];

  systemd.services.paperclip-mcp-free-crypto-news = {
    description = "Free Crypto News MCP Server for Paperclip";
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
      ExecStart = "${bin}/bin/free-crypto-news-mcp";
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
