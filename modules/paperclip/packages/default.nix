{ lib, ... }:

let
  # Toggle optional toolchains — set to false to reduce closure size
  enablePython = true;
  enableGo = true;
  enableRust = true;
  enableCloud = true;
in
{
  imports = [
    ./core.nix
    ./nodejs.nix
    ./database.nix
    ./nix-tools.nix
    ./dev-tools.nix
  ]
  ++ lib.optional enablePython ./python.nix
  ++ lib.optional enableGo ./golang.nix
  ++ lib.optional enableRust ./rust.nix
  ++ lib.optional enableCloud ./cloud.nix;

  # Rootless Docker only — no root daemon to reduce attack surface
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };

  # Automatic shell environment loading from .envrc files
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
