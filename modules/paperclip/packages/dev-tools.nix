{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # Network & debug
    tcpdump
    nmap
    dnsutils              # dig, nslookup
    openssl

    # Editor / terminal
    tmux
    neovim
    fzf
    stow                  # dotfile manager

    # Build essentials
    gnumake
    gcc
    pkg-config
    openssl.dev
    zlib
  ];
}
