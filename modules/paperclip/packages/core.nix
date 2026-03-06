{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    git
    gh                    # GitHub CLI
    jq
    yq-go                # YAML processor
    curl
    wget
    htop
    btop
    tree
    flock
    unzip
    zip
    ripgrep
    fd
    bat
    eza                   # modern ls
    direnv
    starship              # shell prompt
    zoxide                # smart cd
  ];
}
