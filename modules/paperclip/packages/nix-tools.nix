{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    nh                    # nix helper
    nil                   # nix LSP
    nixpkgs-fmt           # nix formatter
  ];
}
