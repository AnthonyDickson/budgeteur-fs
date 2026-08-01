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
        { pkgs, ... }:
        {
          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              dotnet-sdk_10
              nodejs_24
              gleam
              just
              dprint
            ];

            shellHook = ''
              echo "F#/Gleam dev shell"
              echo "  dotnet $(dotnet --version)"
              echo "  $(gleam --version)"

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

