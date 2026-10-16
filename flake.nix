{
  inputs = {
    proxy-flake.url = "github:chpill/proxy-flake";
    nixpkgs.follows = "proxy-flake/nixpkgs";

    zls-flake.url = "github:zigtools/zls";
    zls-flake.inputs.nixpkgs.follows = "proxy-flake/nixpkgs";
    zig-flake.follows = "zls-flake/zig-flake";
  };

  outputs = { nixpkgs, zls-flake, zig-flake, ... } : let
    system = "x86_64-linux";
    zigVersion = "nightly";
    pkgs = nixpkgs.legacyPackages.${system};
    zig-package = zig-flake.packages.${system}.${zigVersion};
    zls-package = zls-flake.packages.${system}.zls;
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = [
        pkgs.zls
        pkgs.entr
        pkgs.opencode
        zig-package
        zls-package
      ];
    };
  };
}
