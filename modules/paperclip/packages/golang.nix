{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    go
    gopls
    golangci-lint
    delve                 # Go debugger
    gotools               # goimports, etc.
  ];
}
