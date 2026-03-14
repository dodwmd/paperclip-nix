# Mermaid MCP server — create and analyse Mermaid diagrams via AI agents.
# Source: https://www.npmjs.com/package/@lepion/mcp-server-mermaid
#
# To update: bump version in mermaid/package.json, regenerate the lock file:
#   cd mermaid && npm install --package-lock-only --ignore-scripts
# Then update npmDepsHash:
#   prefetch-npm-deps mermaid/package-lock.json
{ pkgs, ... }:

let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;

  version = "1.0.8";
  pkgName = "@lepion/mcp-server-mermaid";

  pkg = pkgs.buildNpmPackage {
    pname = "mermaid-mcp";
    inherit version;

    src = ./mermaid;
    npmDepsHash = "sha256-Zp8PtHgcpyOFtUi1ET3hSwaAkof9Tbe7pMB8dnDLT+A=";
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
    name = "mermaid-mcp";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''
      exec node ${pkg}/lib/node_modules/${pkgName}/dist/index.js "$@"
    '';
  };
in
{
  environment.systemPackages = [ bin ];

  systemd.services.paperclip-mcp-mermaid = {
    description = "Mermaid MCP Server for Paperclip";
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
      ExecStart = "${bin}/bin/mermaid-mcp";
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
