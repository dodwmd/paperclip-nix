# WCAG Color Contrast MCP server — color contrast checking and palette tools.
# Source: https://github.com/bryanberger/mcp-wcag-color-contrast
# Bun/TypeScript project — built with bun build, run with bun.
#
# To update: bump rev to latest commit SHA, update hash, regenerate color-palette/package-lock.json
# with pinned versions matching bun.lock, then update npmDepsHash.
{ pkgs, ... }:

let
  shared = import ./_shared.nix;
  hardening = import ../../lib/hardening.nix;
  inherit (shared) serviceUser serviceGroup agentHome mcpRestartDelay;

  gitSrc = pkgs.fetchFromGitHub {
    owner = "bryanberger";
    repo = "mcp-wcag-color-contrast";
    rev = "f893dc971b4240be0a8448dce178ce40f5a39f6a";
    hash = "sha256-Mbd0HRcBc1lhjgPeoXl7B9Hu10YSU1UQXEz8DfQWU74=";
  };

  pkg = pkgs.buildNpmPackage {
    pname = "mcp-wcag-color-contrast";
    version = "1.0.0";

    # Use GitHub source; inject a package-lock.json (with pinned versions from
    # bun.lock) since the upstream repo ships bun.lock only.
    src = gitSrc;
    postPatch = ''
      cp ${./color-palette/package-lock.json} package-lock.json
      cp ${./color-palette/package.json} package.json
    '';

    npmDepsHash = "sha256-AKGQLRBQ3v5yeMQ1wRKmUhz2KCzXiIMx8mvf//zGfaY=";

    # bun is needed to compile src/index.ts via `npm run build`
    nativeBuildInputs = [ pkgs.bun ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/mcp-wcag-color-contrast
      cp -r dist $out/lib/mcp-wcag-color-contrast/
      cp -r node_modules $out/lib/mcp-wcag-color-contrast/node_modules
      runHook postInstall
    '';
  };

  bin = pkgs.writeShellApplication {
    name = "mcp-wcag-color-contrast";
    runtimeInputs = [ pkgs.bun ];
    text = ''
      exec bun run ${pkg}/lib/mcp-wcag-color-contrast/dist/index.js "$@"
    '';
  };
in
{
  environment.systemPackages = [ bin ];

  systemd.services.paperclip-mcp-color-palette = {
    description = "WCAG Color Contrast MCP Server for Paperclip";
    after = [ "network.target" ];
    environment = { HOME = agentHome; };
    serviceConfig = hardening.base // {
      Type = "simple"; User = serviceUser; Group = serviceGroup;
      WorkingDirectory = agentHome; ExecStart = "${bin}/bin/mcp-wcag-color-contrast";
      Restart = "on-failure"; RestartSec = mcpRestartDelay;
      ProtectHome = "tmpfs"; BindPaths = [ agentHome ]; ReadWritePaths = [ agentHome ];
      ProtectProc = "invisible"; ProcSubset = "pid";
    };
    unitConfig = { StartLimitBurst = 3; StartLimitIntervalSec = 120; };
  };
}
