# Context7 MCP server — provides documentation context for AI agents.
# Source: https://www.npmjs.com/package/@upstash/context7-mcp
#
# To update: bump version in context7/package.json, regenerate context7/package-lock.json,
# then update npmDepsHash by running: prefetch-npm-deps context7/package-lock.json
{ pkgs, ... }:

let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;

  version = "2.1.3";

  pkg = pkgs.buildNpmPackage {
    pname = "context7-mcp";
    inherit version;

    src = ./context7;
    npmDepsHash = "sha256-oRxWUr6fdFLC+uMFNYTgypglV4JjTK2CcLVgnslYahk=";
    dontNpmBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/node_modules/@upstash/context7-mcp
      cp -r node_modules/@upstash/context7-mcp/* $out/lib/node_modules/@upstash/context7-mcp/
      cp -r node_modules $out/lib/node_modules/@upstash/context7-mcp/node_modules
      runHook postInstall
    '';
  };

  bin = pkgs.writeShellApplication {
    name = "context7-mcp";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''
      exec node ${pkg}/lib/node_modules/@upstash/context7-mcp/dist/index.js "$@"
    '';
  };
in
{
  environment.systemPackages = [ bin ];

  systemd.services.paperclip-mcp-context7 = {
    description = "Context7 MCP Server for Paperclip";
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
      ExecStart = "${bin}/bin/context7-mcp";
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
