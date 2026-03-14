# Twitter MCP server — read/post tweets via Twitter API.
# Source: https://github.com/EnesCinr/twitter-mcp
# Requires: TWITTER_API_KEY, TWITTER_API_SECRET, TWITTER_ACCESS_TOKEN, TWITTER_ACCESS_TOKEN_SECRET
{ pkgs, ... }:
let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;
  version = "0.2.0";
  pkgName = "@enescinar/twitter-mcp";
  pkg = pkgs.buildNpmPackage {
    pname = "twitter-mcp"; inherit version;
    src = ./twitter;
    npmDepsHash = "sha256-KtKOqsizyQ2o1ja/0JiiXusYEGhBrfcs7VEziRnb9sU=";
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
    name = "twitter-mcp";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''exec node ${pkg}/lib/node_modules/${pkgName}/build/index.js "$@"'';
  };
in
{
  environment.systemPackages = [ bin ];
  systemd.services.paperclip-mcp-twitter = {
    description = "Twitter MCP Server for Paperclip";
    after = [ "network.target" ];
    environment = { NODE_ENV = "production"; HOME = agentHome;
      # Twitter API credentials must be set via paperclip-env secret
    };
    serviceConfig = hardening.base // {
      Type = "simple"; User = serviceUser; Group = serviceGroup;
      WorkingDirectory = agentHome; ExecStart = "${bin}/bin/twitter-mcp";
      Restart = "on-failure"; RestartSec = mcpRestartDelay;
      ProtectHome = "tmpfs"; BindPaths = [ agentHome ]; ReadWritePaths = [ agentHome ];
      ProtectProc = "invisible"; ProcSubset = "pid";
    };
    unitConfig = { StartLimitBurst = 3; StartLimitIntervalSec = 120; };
  };
}
