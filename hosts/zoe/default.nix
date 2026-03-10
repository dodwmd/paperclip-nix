{ ... }:

{
  # N5105 (Jasper Lake) has no AVX2 — use the bun baseline build.
  # When nixpkgs bumps bun, update the hash:
  #   nix store prefetch-file --hash-type sha256 \
  #     "https://github.com/oven-sh/bun/releases/download/bun-v<VERSION>/bun-linux-x64-baseline.zip"
  nixpkgs.overlays = [
    (_final: prev: {
      bun = prev.bun.overrideAttrs (_old: {
        src = prev.fetchzip {
          url = "https://github.com/oven-sh/bun/releases/download/bun-v${prev.bun.version}/bun-linux-x64-baseline.zip";
          hash = "sha256-ZWTs4ApH0BsATxrE1DSuqCETIrNZZxdG8xtN0NinNBw="; # bun 1.3.10
        };
      });
    })
  ];

  imports = [
    ./hardware-configuration.nix
    ./networking.nix
    ./users.nix

    ../../modules/core/boot.nix
    ../../modules/core/nix-settings.nix
    ../../modules/core/locale.nix

    ../../modules/services/openssh.nix
    ../../modules/services/tmux.nix
    ../../modules/services/postgresql.nix
    ../../modules/services/postgresql-backup.nix
    ../../modules/services/nfs-backup.nix
    ../../modules/services/nginx.nix
    ../../modules/services/monitoring.nix
    ../../modules/services/muninndb.nix

    ../../modules/paperclip/default.nix
    ../../modules/secrets.nix
  ];

  networking.hostName = "zoe";

  # Disable doc generation — server doesn't need it, and python3.12-doc
  # is currently broken in nixos-unstable (Sphinx/docutils incompatibility)
  documentation.enable = false;

  # Thermal management for fanless N5105 NUC
  powerManagement.cpuFreqGovernor = "ondemand";

  system.stateVersion = "25.05";
}
