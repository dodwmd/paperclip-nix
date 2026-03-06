{ ... }:

{
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
