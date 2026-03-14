# RSS MCP server — fetch and parse RSS/Atom feeds.
# Source: https://www.npmjs.com/package/rss-mcp
#
# To update: bump version in rss-mcp/package.json, regenerate the lock file:
#   cd rss-mcp && npm install --package-lock-only --ignore-scripts
# Then update npmDepsHash:
#   nix run nixpkgs#prefetch-npm-deps -- rss-mcp/package-lock.json
{ pkgs, ... }:

let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;

  version = "1.0.1";
  pkgName = "rss-mcp";

  pkg = pkgs.buildNpmPackage {
    pname = "rss-mcp";
    inherit version;

    src = ./rss-mcp;
    npmDepsHash = "sha256-EExBIZ6zd7rhM64z+nb7MZrGipkkKO/emDfjUr6YqO4=";
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
    name = "rss-mcp";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''
      exec node ${pkg}/lib/node_modules/${pkgName}/dist/index.js "$@"
    '';
  };
in
{
  environment.systemPackages = [ bin ];

  systemd.services.paperclip-mcp-rss = {
    description = "RSS MCP Server for Paperclip";
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
      ExecStart = "${bin}/bin/rss-mcp";
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
