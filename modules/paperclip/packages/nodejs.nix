{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    nodejs_22
    nodePackages.pnpm
    nodePackages.npm
    nodePackages.yarn
    nodePackages.typescript
    nodePackages.typescript-language-server
    nodePackages.prettier
  ];
}
