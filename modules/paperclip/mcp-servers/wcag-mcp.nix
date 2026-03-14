# WCAG MCP server — Web Content Accessibility Guidelines checker.
# Source: https://github.com/gotalab/wcag-mcp
{ pkgs, ... }:
let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;
  version = "0.1.0-beta";
  pkgName = "wcag-mcp";
  pkg = pkgs.buildNpmPackage {
    pname = pkgName; inherit version;
    src = ./wcag;
    npmDepsHash = "sha256-iI3pmIcFOr1qpg5YyWEadEGI0MA78kxnSMsVIZolwFA=";
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
    name = "wcag-mcp";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''exec node ${pkg}/lib/node_modules/${pkgName}/index.js "$@"'';
  };
in
{
  environment.systemPackages = [ bin ];
  systemd.services.paperclip-mcp-wcag = {
    description = "WCAG MCP Server for Paperclip";
    after = [ "network.target" ];
    environment = { NODE_ENV = "production"; HOME = agentHome; };
    serviceConfig = hardening.base // {
      Type = "simple"; User = serviceUser; Group = serviceGroup;
      WorkingDirectory = agentHome; ExecStart = "${bin}/bin/wcag-mcp";
      Restart = "on-failure"; RestartSec = mcpRestartDelay;
      ProtectHome = "tmpfs"; BindPaths = [ agentHome ]; ReadWritePaths = [ agentHome ];
      ProtectProc = "invisible"; ProcSubset = "pid";
    };
    unitConfig = { StartLimitBurst = 3; StartLimitIntervalSec = 120; };
  };
}
