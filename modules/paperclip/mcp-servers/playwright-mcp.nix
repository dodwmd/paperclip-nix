# Playwright MCP server — browser automation (covers both playwright and puppeteer agents).
# Source: https://github.com/microsoft/playwright-mcp
# Note: requires Chromium/Firefox browsers; run `playwright install` on first use.
{ pkgs, ... }:
let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;
  version = "0.0.68";
  pkgName = "@playwright/mcp";
  pkg = pkgs.buildNpmPackage {
    pname = "playwright-mcp"; inherit version;
    src = ./playwright;
    npmDepsHash = "sha256-9RKMZyYatxaA02GxHfejAMqFJ8aX1F/n4I7OX1IT6wI=";
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
    name = "playwright-mcp";
    runtimeInputs = [ pkgs.nodejs_22 pkgs.chromium ];
    text = ''exec node ${pkg}/lib/node_modules/${pkgName}/cli.js "$@"'';
  };
in
{
  environment.systemPackages = [ bin ];
  systemd.services.paperclip-mcp-playwright = {
    description = "Playwright MCP Server for Paperclip";
    after = [ "network.target" ];
    environment = {
      NODE_ENV = "production"; HOME = agentHome;
      PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    };
    serviceConfig = hardening.base // {
      Type = "simple"; User = serviceUser; Group = serviceGroup;
      WorkingDirectory = agentHome; ExecStart = "${bin}/bin/playwright-mcp";
      Restart = "on-failure"; RestartSec = mcpRestartDelay;
      ProtectHome = "tmpfs"; BindPaths = [ agentHome ]; ReadWritePaths = [ agentHome ];
      ProtectProc = "invisible"; ProcSubset = "pid";
    };
    unitConfig = { StartLimitBurst = 3; StartLimitIntervalSec = 120; };
  };
}
