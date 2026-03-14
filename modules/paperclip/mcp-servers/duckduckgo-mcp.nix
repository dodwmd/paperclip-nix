# DuckDuckGo MCP server — web search via DuckDuckGo.
# Source: https://github.com/nickclyde/duckduckgo-mcp-server
{ pkgs, ... }:
let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;
  version = "0.1.2";
  pkgName = "duckduckgo-mcp-server";
  pkg = pkgs.buildNpmPackage {
    pname = pkgName; inherit version;
    src = ./duckduckgo;
    npmDepsHash = "sha256-6nFY4iVDmaC0m6shwLjQna2BUUVPh4QsFitofdvWatU=";
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
    name = "duckduckgo-mcp-server";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''exec node ${pkg}/lib/node_modules/${pkgName}/build/index.js "$@"'';
  };
in
{
  environment.systemPackages = [ bin ];
  systemd.services.paperclip-mcp-duckduckgo = {
    description = "DuckDuckGo MCP Server for Paperclip";
    after = [ "network.target" ];
    environment = { NODE_ENV = "production"; HOME = agentHome; };
    serviceConfig = hardening.base // {
      Type = "simple"; User = serviceUser; Group = serviceGroup;
      WorkingDirectory = agentHome; ExecStart = "${bin}/bin/duckduckgo-mcp-server";
      Restart = "on-failure"; RestartSec = mcpRestartDelay;
      ProtectHome = "tmpfs"; BindPaths = [ agentHome ]; ReadWritePaths = [ agentHome ];
      ProtectProc = "invisible"; ProcSubset = "pid";
    };
    unitConfig = { StartLimitBurst = 3; StartLimitIntervalSec = 120; };
  };
}
