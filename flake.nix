{
  description = "Run OpenAI Codex models inside the Claude Code harness";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          cliproxyapi = pkgs.callPackage ./packages/cliproxyapi.nix { };
          default = pkgs.callPackage ./packages/cliproxyapi.nix { };
        }
      );

      homeManagerModules = {
        claudex = import ./modules/home-manager.nix;
        default = import ./modules/home-manager.nix;
      };

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          moduleConfig = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              self.homeManagerModules.default
              {
                home = {
                  username = "claudex-test";
                  homeDirectory = "/home/claudex-test";
                  stateVersion = "26.05";
                };
                programs.claudex.enable = true;
              }
            ];
          };
        in
        {
          inherit (self.packages.${system}) cliproxyapi;
          module = moduleConfig.activationPackage;
          compatibility-policy = pkgs.runCommand "claudex-compatibility-policy-check" { } ''
            launcher=${moduleConfig.activationPackage}/home-path/bin/claudex
            grep -F 'export CLAUDE_CODE_DISABLE_WORKFLOWS=1' "$launcher"
            grep -F 'disableClaudeAiConnectors' "$launcher"
            grep -F 'disableRemoteControl' "$launcher"
            grep -F 'disableWorkflows' "$launcher"
            grep -F 'Remote Control is disabled for the Codex gateway' "$launcher"
            touch $out
          '';
          format = pkgs.runCommand "claudex-format-check" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
            nixfmt --check ${./flake.nix} ${./modules/home-manager.nix} ${./packages/cliproxyapi.nix}
            touch $out
          '';
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.go
              pkgs.nixfmt
              pkgs.shellcheck
            ];
          };
        }
      );
    };
}
