{
  description = "Mind Goblin - Bullet journal todo.txt to CalDAV sync";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        haskellPackages = pkgs.haskellPackages;
        
        # Define the package
        mg = haskellPackages.callCabal2nix "mg" ./. {};
        
      in {
        packages = {
          default = mg;
          mg = mg;
        };

        apps = {
          default = flake-utils.lib.mkApp {
            drv = mg;
            exePath = "/bin/mg";
          };
          mg = flake-utils.lib.mkApp {
            drv = mg;
            exePath = "/bin/mg";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Haskell toolchain
            ghc
            cabal-install
            haskell-language-server
            
            # Code formatting and linting
            haskellPackages.fourmolu
            haskellPackages.hlint
            
            # Dependencies for our project
            haskellPackages.megaparsec
            haskellPackages.text
            haskellPackages.time
            haskellPackages.uuid
            haskellPackages.containers
            haskellPackages.filepath
            haskellPackages.directory
            haskellPackages.process
            haskellPackages.bytestring
            haskellPackages.iCalendar
            haskellPackages.mtl
            haskellPackages.transformers
            haskellPackages.optparse-applicative
            haskellPackages.temporary
            
            # Testing
            haskellPackages.hspec
            haskellPackages.hspec-discover
            haskellPackages.QuickCheck
            
            # vdirsyncer for CalDAV operations
            vdirsyncer
          ];
          
          shellHook = ''
            echo "Mind Goblin development environment"
            echo "Run 'cabal build' to build the project"
            echo "Run 'cabal test' to run tests"
            echo "Run 'fourmolu -i src/ test/' to format code"
            echo "Run 'hlint src/ test/' to lint code"
            echo "vdirsyncer is available for CalDAV operations"
          '';
        };

        # NixOS module for automatic syncing
        nixosModules.default = { config, lib, pkgs, ... }:
          with lib;
          let
            cfg = config.services.mind-goblin;
          in {
            options.services.mind-goblin = {
              enable = mkEnableOption "Mind Goblin todo.txt to CalDAV sync";
              
              user = mkOption {
                type = types.str;
                description = "User to run Mind Goblin sync for";
              };
              
              interval = mkOption {
                type = types.str;
                default = "*:0/5";  # Every 5 minutes
                description = "How often to sync (systemd OnCalendar format)";
              };
              
              todoFile = mkOption {
                type = types.str;
                default = "~/todo.txt";
                description = "Path to todo.txt file";
              };
            };
            
            config = mkIf cfg.enable {
              systemd.user.services.mind-goblin-sync = {
                description = "Mind Goblin CalDAV sync";
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${mg}/bin/mg sync --file ${cfg.todoFile}";
                };
              };
              
              systemd.user.timers.mind-goblin-sync = {
                description = "Mind Goblin sync timer";
                wantedBy = [ "timers.target" ];
                timerConfig = {
                  OnCalendar = cfg.interval;
                  Persistent = true;
                };
              };
              
              environment.systemPackages = [ mg pkgs.vdirsyncer ];
            };
          };
      });
}