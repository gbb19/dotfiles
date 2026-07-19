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

              # GPG config
              programs.gpg = {
                enable = true;
              };

              # GPG Agent config for macOS (caching password for 4 hours / 14400 seconds)
              home.file.".gnupg/gpg-agent.conf".text = ''
                default-cache-ttl 14400
                max-cache-ttl 14400
                default-cache-ttl-ssh 14400
                max-cache-ttl-ssh 14400
                pinentry-program ${pkgs.pinentry-curses}/bin/pinentry-curses
              '';

              home.packages = with pkgs; [
                git
                neovim
                gcc
                gnumake
                tree-sitter
                zoxide
                unzip
                zip
                ripgrep
                tmux
                fzf
                rsync
                curl
                tree
                gnupg
                tree
                fd
                bat
                delta
                tailscale
                htop
                colima
                docker
                docker-compose
                devcontainer
                postgresql
                kitty
                ghq
                sql-formatter
              ];
            }
          ];
        };
    };
}
