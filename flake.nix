{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    fenix.url = "github:nix-community/fenix";
  };
  outputs = inputs @ {
    nixpkgs,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];
      imports = [];
      perSystem = {pkgs, ...}: let
        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (with pkgs; [
          openssl
          stdenv.cc.cc.lib
          fontconfig
          freetype
          wayland
          xorg.libX11
          libxkbcommon
          libGL
        ]);

        nix-crucible' = {
          pkgs,
          lib,
          gn,
          makeRustPlatform,
          clangStdenv,
          ninja,
          fetchFromGitHub,
          linkFarm,
          fetchgit,
          runCommand,
          freetype,
          fontconfig,
          libGL,
          ...
        }: let
          inherit (inputs.fenix.packages.${pkgs.system}.minimal) toolchain;
          rustPlatform = makeRustPlatform {
            cargo = toolchain;
            rustc = toolchain;
          };
        in
          rustPlatform.buildRustPackage.override {stdenv = clangStdenv;} {
            pname = "nix-crucible";
            version = "unstable";
            src = ./.;
            cargoLock = {
              lockFile = ./Cargo.lock;
              outputHashes = {
                "morphorm-0.6.4" = "sha256-JZ49mB44q/EQbNMdflcnJVNjbnY0dg6+gAjVX4mDhJg=";
                "selectors-0.23.0" = "sha256-9nD2YY9Z9YDrQqy99T02FCC5Q7oGjJamPP/ciTmCkUc=";
              };
            };

            SKIA_SOURCE_DIR = let
              repo = fetchFromGitHub {
                owner = "rust-skia";
                repo = "skia";
                # see rust-skia:skia-bindings/Cargo.toml#package.metadata skia
                rev = "m126-0.74.2";
                hash = "sha256-4l6ekAJy+pG27hBGT6A6LLRwbsyKinJf6PP6mMHwaAs=";
              };
              # The externals for skia are taken from skia/DEPS
              externals = linkFarm "skia-externals" (
                lib.mapAttrsToList (name: value: {
                  inherit name;
                  path = fetchgit value;
                }) (lib.importJSON ./skia-externals.json)
              );
            in
              runCommand "source" {} ''
                cp -R ${repo} $out
                chmod -R +w $out
                ln -s ${externals} $out/third_party/externals
              '';
            SKIA_GN_COMMAND = "${gn}/bin/gn";
            SKIA_NINJA_COMMAND = "${ninja}/bin/ninja";

            buildInputs = with pkgs; [
              openssl
              rustPlatform.bindgenHook
              freetype
              fontconfig
              wayland
              libGL
            ];

            nativeBuildInputs = with pkgs; [
              python3
              pkg-config
            ];

            # disallowedReferences = [SKIA_SOURCE_DIR];

            inherit LD_LIBRARY_PATH;
          };

        nix-crucible = pkgs.callPackage nix-crucible' {};
      in {
        packages.default = nix-crucible;

        devShells.default = pkgs.mkShell.override {stdenv = pkgs.clangStdenv;} {
          buildInputs = with pkgs; [];
          inputsFrom = [nix-crucible];
          inherit LD_LIBRARY_PATH;
          SKIA_GN_COMMAND = pkgs.lib.getExe pkgs.gn;
          SKIA_NINJA_COMMAND = pkgs.lib.getExe pkgs.ninja;
        };
      };
    };
}
