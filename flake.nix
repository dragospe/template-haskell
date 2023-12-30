{
  # templated from https://github.com/jonascarpay/template-haskell
  description = "PKGNAME";

  inputs.pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/release-23.05";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = inputs@{ self, pre-commit-hooks, ... }:
    let
      overlay = final: prev: {
        haskell = prev.haskell // {
          packageOverrides = hfinal: hprev:
            prev.haskell.packageOverrides hfinal hprev // {
              PKGNAME = hfinal.callCabal2nix "PKGNAME" ./. { };
            };
        };
        PKGNAME = final.haskell.lib.compose.justStaticExecutables final.haskellPackages.PKGNAME;
      };
      perSystem = system:
        let
          pkgs = import inputs.nixpkgs { inherit system; overlays = [ overlay ]; };
          hspkgs = pkgs.haskellPackages;
        in
        {
          checks = {
            pre-commit-check = pre-commit-hooks.lib.${system}.run {
              src = ./.;
              hooks = {

                # Nix
                nixpkgs-fmt.enable = true;
                statix.enable = true;
                deadnix.enable = true;

                # Haskell
                hlint.enable = true;
                fourmolu.enable = true;
                cabal-fmt.enable = true;
                #stan.enable = true; Broken, as of 2023-12-30

                # Other
                typos = { enable = true; };
              };

            };
          };

          devShell = hspkgs.shellFor {
            inherit (self.checks.${system}.pre-commit-check) shellHook;
            withHoogle = true;
            packages = p: [ p.PKGNAME ];
            buildInputs = [
              # Haskell
              hspkgs.cabal-install # the bog-standard "cabal" command
              hspkgs.cabal-fmt # cabal formatter
              hspkgs.haskell-language-server # LSP
              hspkgs.hlint # linter for haskell code
              hspkgs.apply-refact # automatic refactorings, ties in with hlint
              hspkgs.fourmolu # formatter for haskell code
              hspkgs.zlib # Needed for... reasons. Google "zlib haskell nix"
              #hspkgs.stan # Broken, as of 2023-12-30

              # Nix
              pkgs.deadnix # Dead code analysis for nix
              pkgs.statix # static analysis for nix
              pkgs.nixpkgs-fmt # formatting for nix

              # Shell
              pkgs.bashInteractive
            ];
          };
          defaultPackage = pkgs.PKGNAME;
        };
    in
    { inherit overlay; } // inputs.flake-utils.lib.eachDefaultSystem perSystem;
}
