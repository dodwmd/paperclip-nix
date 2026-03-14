# Reddit MCP server — browse and search Reddit posts/comments.
# Source: https://github.com/adhikasp/mcp-reddit
{ pkgs, ... }:
let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;
  version = "1.1.8";
  pkgName = "mcp-reddit";
  pkg = pkgs.buildNpmPackage {
    pname = pkgName; inherit version;
    src = ./reddit;
    npmDepsHash = "sha256-O/aBMXwC2s2myn4UaF8sL2r2a7nXQn9pQwB+ii0GzJE=";
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
    name = "mcp-reddit";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''exec node ${pkg}/lib/node_modules/${pkgName}/dist/server.js "$@"'';
  };
in
{
  environment.systemPackages = [ bin ];
  systemd.services.paperclip-mcp-reddit = {
    description = "Reddit MCP Server for Paperclip";
    after = [ "network.target" ];
    environment = { NODE_ENV = "production"; HOME = agentHome; };
    serviceConfig = hardening.base // {
      Type = "simple"; User = serviceUser; Group = serviceGroup;
      WorkingDirectory = agentHome; ExecStart = "${bin}/bin/mcp-reddit";
      Restart = "on-failure"; RestartSec = mcpRestartDelay;
      ProtectHome = "tmpfs"; BindPaths = [ agentHome ]; ReadWritePaths = [ agentHome ];
      ProtectProc = "invisible"; ProcSubset = "pid";
    };
    unitConfig = { StartLimitBurst = 3; StartLimitIntervalSec = 120; };
  };
}
