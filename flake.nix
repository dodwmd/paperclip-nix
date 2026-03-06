{
  description = "Paperclip NixOS deployment for zoe.home.dodwell.us";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, agenix, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      nixosConfigurations.zoe = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit self; };
        modules = [
          disko.nixosModules.disko
          agenix.nixosModules.default
          ./hosts/zoe/disk-config.nix
          ./hosts/zoe
        ];
      };

      # Expose agenix binary so `nix run .#agenix` works (avoids Go build cache issues)
      packages.${system}.agenix = agenix.packages.${system}.default;

      # Verify the configuration builds
      checks.${system}.default = self.nixosConfigurations.zoe.config.system.build.toplevel;

      # Formatter for `nix fmt`
      formatter.${system} = pkgs.nixpkgs-fmt;

      # Dev shell for working on the nix config itself
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          git
          curl
          jq
          nixpkgs-fmt
          agenix.packages.${system}.default
          age           # needed for make generate-host-keys
          openssh       # needed for ssh-keygen in make generate-host-keys
        ];
        shellHook = ''
          echo "Paperclip NixOS dev shell — run 'make help' for available commands"
        '';
      };
    };
}
