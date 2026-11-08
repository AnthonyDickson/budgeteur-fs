{
  description = "F#/Gleam development environment";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      perSystem =
        { system, ... }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            # kotlin-lsp is a proprietary JetBrains binary (see
            # `nix/packages/kotlin-lsp`); allow it by name and nothing else.
            config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [ "kotlin-lsp" ];
          };
          # JetBrains' official language server, pinned in `nix/packages/kotlin-lsp`.
          kotlin-lsp = pkgs.callPackage ./nix/packages/kotlin-lsp { };
        in
        {
          _module.args.pkgs = pkgs;

          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              dotnet-sdk_10
              # Kotlin port PoC in server-kt/
              jdk21
              gradle
              kotlin-lsp
              nodejs_24
              gleam
              just
              dprint
            ];

            shellHook = ''
              echo "F#/Gleam dev shell"
              echo "  dotnet $(dotnet --version)"
              echo "  $(gleam --version)"

              # A build that has expired refuses to start, and the editor only
              # shows the language server failing, so report the pinned build's age.
              kotlin_lsp_age=$(( ($(date +%s) - ${toString kotlin-lsp.releasedEpoch}) / 86400 ))
              if [ "$kotlin_lsp_age" -ge 25 ]; then
                echo "WARNING: kotlin-lsp ${kotlin-lsp.version} was released ${kotlin-lsp.released}, $kotlin_lsp_age days ago."
                echo "  JetBrains builds expire about a month after release, so it may already refuse to start."
                echo "  Update the pin with \`just update-kotlin-lsp\`, then re-enter this shell."
              fi
              unset kotlin_lsp_age

              # Restore local dotnet tools (fantomas, fsharplint, sqlhydra, etc.)
              if [ -f server/dotnet-tools.json ]; then
                pushd server
                dotnet tool restore
                popd
              fi
            '';

            env.DOTNET_ROOT = "${pkgs.dotnet-sdk_10}";
          };
        };

      flake = { };

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    };
}

