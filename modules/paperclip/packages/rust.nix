{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    rustup                # for building native deps
  ];
}
