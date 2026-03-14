# AntV Chart MCP server — generate charts and data visualizations.
# Source: https://github.com/antvis/mcp-server-chart
{ pkgs, ... }:
let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;
  version = "0.9.10";
  pkgName = "@antv/mcp-server-chart";
  pkg = pkgs.buildNpmPackage {
    pname = "mcp-server-chart"; inherit version;
    src = ./chart;
    npmDepsHash = "sha256-zZeDgLoJ8p4ozQX1xpW+5BO5siC6xrMK/Yks8P9MJlA=";
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
    name = "mcp-server-chart";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''exec node ${pkg}/lib/node_modules/${pkgName}/build/index.js "$@"'';
  };
in
{
  environment.systemPackages = [ bin ];
  systemd.services.paperclip-mcp-chart = {
    description = "AntV Chart MCP Server for Paperclip";
    after = [ "network.target" ];
    environment = { NODE_ENV = "production"; HOME = agentHome; };
    serviceConfig = hardening.base // {
      Type = "simple"; User = serviceUser; Group = serviceGroup;
      WorkingDirectory = agentHome; ExecStart = "${bin}/bin/mcp-server-chart";
      Restart = "on-failure"; RestartSec = mcpRestartDelay;
      ProtectHome = "tmpfs"; BindPaths = [ agentHome ]; ReadWritePaths = [ agentHome ];
      ProtectProc = "invisible"; ProcSubset = "pid";
    };
    unitConfig = { StartLimitBurst = 3; StartLimitIntervalSec = 120; };
  };
}
