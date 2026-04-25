{
  description = "Declarative Zotero plugin packaging for Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      pluginLib = system:
        import ./lib {
          inherit (pkgsFor system) lib stdenvNoCC unzip jq;
        };

      bundledPlugins = system:
        import ./pkgs {
          inherit (pkgsFor system) lib fetchurl;
          inherit (pluginLib system) mkZoteroPlugin;
        };
    in
    {
      # Factory for packaging arbitrary Zotero plugins.
      # Usage:
      #   nix-zotero-plugins.lib.${system}.mkZoteroPlugin { pname, version, src, meta ? {} }
      lib = forAllSystems (system: pluginLib system);

      # Pre-packaged curated plugins.
      packages = forAllSystems (system: bundledPlugins system);

      # Home Manager module: programs.zotero-plugins.{enable, profileName, plugins}.
      homeManagerModules.default = import ./modules/home-manager.nix;

      # Overlay exposing pkgs.zoteroPlugins.* for non-flake consumers.
      overlays.default = final: prev:
        let
          zlib = import ./lib { inherit (prev) lib stdenvNoCC unzip jq; };
          plugins = import ./pkgs {
            inherit (prev) lib fetchurl;
            inherit (zlib) mkZoteroPlugin;
          };
        in {
          zoteroPlugins = plugins // { inherit (zlib) mkZoteroPlugin; };
        };
    };
}
