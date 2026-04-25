{
  inputs = {
    proxy-flake.url = "github:chpill/proxy-flake";
    nixpkgs.follows = "proxy-flake/nixpkgs";
    zig-flake.url = "github:mitchellh/zig-overlay";
    zig-flake.inputs.nixpkgs.follows = "proxy-flake/nixpkgs";
  };

  outputs = { nixpkgs, zig-flake, ... } : let
    system = "x86_64-linux";
    zigVersion = "0.16.0";
    pkgs = nixpkgs.legacyPackages.${system};
    zig-package = zig-flake.packages.${system}.${zigVersion};
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = [
        pkgs.zls
        pkgs.entr
        zig-package
      ];
    };
  };
}
