{
  inputs = {
    proxy-flake.url = "github:chpill/proxy-flake";
    nixpkgs.follows = "proxy-flake/nixpkgs";

    zls-flake.url = "github:zigtools/zls";
    zls-flake.inputs.nixpkgs.follows = "proxy-flake/nixpkgs";
    zig-flake.follows = "zls-flake/zig-flake";
  };

  outputs = { self, nixpkgs, zls-flake, zig-flake, ... } : let
    systems = [ "x86_64-linux" "aarch64-linux" ];
    zigVersion = "zig_0_17_0";
    targets = [
      "x86_64-linux-musl"
      "aarch64-linux-musl"
      "aarch64-macos"
      "x86_64-macos"
    ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems f;
    nativeTarget = system:
      if system == "x86_64-linux" then "x86_64-linux-musl"
      else if system == "aarch64-linux" then "aarch64-linux-musl"
      else throw "unsupported system ${system}";

    # The canonical smoke fixture: hash m2yv... maps to glyph ↧ (U+21A7),
    # hue 239 = rgb(32,35,223); see the unit tests in src/main.zig.
    sampleIn = "/nix/store/m2yvkibsf6icc5csqjkm5ldbwgml7zs0-libmnl-1.0.5.drv";
    sampleOut = "⬡ ↧-libmnl-1.0.5.drv";

    smokeCmd = run: ''
      actual=$(printf '%s\n' '${sampleIn}' | ${run} --color=never)
      test "$actual" = '${sampleOut}' || { echo "unexpected output: $actual"; exit 1; }
    '';
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      zig-package = zig-flake.packages.${system}.${zigVersion};

      mojipath-target = target: pkgs.stdenv.mkDerivation {
        pname = "mojipath-${target}";
        version = "0.0.1";
        src = ./.;

        nativeBuildInputs = [ zig-package ];

        dontFixup = true;

        preBuild = ''
          export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-global-cache
          export ZIG_LOCAL_CACHE_DIR=$TMPDIR/zig-local-cache
        '';

        buildPhase = ''
          runHook preBuild
          zig build install -Doptimize=ReleaseFast -Dtarget=${target} --prefix $out
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          runHook postInstall
        '';
      };

      perTarget = builtins.listToAttrs (map (target: {
        name = "mojipath-${target}";
        value = mojipath-target target;
      }) targets);
    in perTarget // {
      default = perTarget."mojipath-${nativeTarget system}";
    });

    checks = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      zig-package = zig-flake.packages.${system}.${zigVersion};
      pkgs' = self.packages.${system};

      # Executes ${run} with the sample input; run embeds the binary path and
      # any emulator wrapper.
      mkSmoke = target: nativeBuildInputs: run:
        pkgs.runCommand "mojipath-smoke-${target}" { inherit nativeBuildInputs; }
          (smokeCmd run + "\necho ok > $out");

      # macOS binaries cannot execute on Linux hosts; verify the Mach-O
      # magic instead (0xfeedfacf, little-endian: cf fa ed fe).
      mkMachoMagic = target:
        pkgs.runCommand "mojipath-macho-${target}" { } ''
          magic=$(head -c 4 ${pkgs'."mojipath-${target}"}/bin/mojipath | od -An -tx1 | tr -d ' \n')
          test "$magic" = "cffaedfe" || { echo "not a Mach-O binary: $magic"; exit 1; }
          echo ok > $out
        '';

      unitTests = pkgs.stdenv.mkDerivation {
        pname = "mojipath-unit-tests";
        version = "0.0.1";
        src = ./.;
        nativeBuildInputs = [ zig-package ];
        dontFixup = true;
        preBuild = ''
          export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-global-cache
          export ZIG_LOCAL_CACHE_DIR=$TMPDIR/zig-local-cache
        '';
        buildPhase = ''
          runHook preBuild
          zig build test
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          touch $out
          runHook postInstall
        '';
      };

      linuxChecks = {
        mojipath-unit-tests = unitTests;
        mojipath-macho-aarch64-macos = mkMachoMagic "aarch64-macos";
        mojipath-macho-x86_64-macos = mkMachoMagic "x86_64-macos";
      };
    in
      if system == "x86_64-linux" then linuxChecks // {
        mojipath-x86_64-linux-musl =
          mkSmoke "x86_64-linux-musl" [ ] "${pkgs'.mojipath-x86_64-linux-musl}/bin/mojipath";
        mojipath-aarch64-linux-musl =
          mkSmoke "aarch64-linux-musl" [ pkgs.qemu ]
            "qemu-aarch64 ${pkgs'.mojipath-aarch64-linux-musl}/bin/mojipath";
      } else if system == "aarch64-linux" then linuxChecks // {
        mojipath-aarch64-linux-musl =
          mkSmoke "aarch64-linux-musl" [ ] "${pkgs'.mojipath-aarch64-linux-musl}/bin/mojipath";
      } else linuxChecks);

    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      zig-package = zig-flake.packages.${system}.${zigVersion};
      zls-package = zls-flake.packages.${system}.zls;
    in {
      default = pkgs.mkShell {
        packages = [
          pkgs.zls
          pkgs.entr
          pkgs.opencode
          pkgs.qemu
          zig-package
          zls-package
        ];
      };
    });
  };
}
