{
  description = "My Home Manager config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # Auto-detect username and home directory from environment variables,
      # falling back to "nenz" and "/Users/nenz" if evaluated in pure mode.
      username = let envUser = builtins.getEnv "USER"; in if envUser == "" then "nenz" else envUser;
      homeDirectory = let envHome = builtins.getEnv "HOME"; in if envHome == "" then "/Users/nenz" else envHome;
    in {
      homeConfigurations."default" =
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [
            {
              home.username = username;
              home.homeDirectory = homeDirectory;

              home.stateVersion = "25.11";

              manual.manpages.enable = false;
              manual.json.enable = false;

              programs.home-manager.enable = true;
              home.packages = with pkgs; [
                git
                neovim
                zoxide
                unzip
                zip
                ripgrep
                tmux
                fzf
                rsync
                curl
                gnupg
                fd
                bat
                tailscale
                htop
                colima
                docker
                docker-compose
                devcontainer
                postgresql
                kitty
              ];
            }
          ];
        };
    };
}
