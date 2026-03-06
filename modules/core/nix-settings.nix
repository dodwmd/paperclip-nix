{ ... }:

{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    trusted-users = [ "root" "dodwmd" ];
  };

  # Weekly garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Limit journal size to prevent disk fill on 128GB NVMe
  services.journald.extraConfig = ''
    SystemMaxUse=2G
    SystemKeepFree=4G
  '';
}
