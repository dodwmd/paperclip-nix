# Desktop Commander MCP server — terminal commands and file system operations.
# Source: https://github.com/wonderwhy-er/DesktopCommanderMCP
# Note: hardening is relaxed — this server needs broad filesystem access by design.
{ pkgs, ... }:
let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;
  version = "0.2.38";
  pkgName = "@wonderwhy-er/desktop-commander";
  pkg = pkgs.buildNpmPackage {
    pname = "desktop-commander"; inherit version;
    src = ./desktop-commander;
    npmDepsHash = "sha256-L7HjNTv7tDsuTPw0VL/CVgJngjnvhvhp0no1J6/Z9CA=";
    dontNpmBuild = true;
    # Multiple transitive deps (puppeteer, ripgrep, etc.) try to download binaries
    # during postinstall. Skip all scripts — we use system packages instead.
    # Note: npm ci already uses --ignore-scripts, but npm rebuild runs after and
    # executes postinstall scripts. npmRebuildFlags suppresses those.
    npmRebuildFlags = [ "--ignore-scripts" ];
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/node_modules/${pkgName}
      cp -r node_modules/${pkgName}/* $out/lib/node_modules/${pkgName}/
      cp -r node_modules $out/lib/node_modules/${pkgName}/node_modules
      runHook postInstall
    '';
  };
  bin = pkgs.writeShellApplication {
    name = "desktop-commander";
    runtimeInputs = [ pkgs.nodejs_22 pkgs.ripgrep ];
    text = ''exec node ${pkg}/lib/node_modules/${pkgName}/dist/index.js "$@"'';
  };
in
{
  environment.systemPackages = [ bin ];
  systemd.services.paperclip-mcp-desktop-commander = {
    description = "Desktop Commander MCP Server for Paperclip";
    after = [ "network.target" ];
    environment = { NODE_ENV = "production"; HOME = agentHome; };
    serviceConfig = hardening.base // {
      Type = "simple"; User = serviceUser; Group = serviceGroup;
      WorkingDirectory = agentHome; ExecStart = "${bin}/bin/desktop-commander";
      Restart = "on-failure"; RestartSec = mcpRestartDelay;
      ProtectHome = "tmpfs"; BindPaths = [ agentHome ]; ReadWritePaths = [ agentHome ];
      ProtectProc = "invisible"; ProcSubset = "pid";
    };
    unitConfig = { StartLimitBurst = 3; StartLimitIntervalSec = 120; };
  };
}
