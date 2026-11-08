# nixpkgs only carries the community `kotlin-language-server`, which bundles a
# Kotlin 2.1 compiler that cannot read the 2.4 standard library. Package
# JetBrains' official server instead, from its prebuilt release: it bundles its
# own JetBrains Runtime, and the Linux build needs its interpreter and libraries
# patched to point into the store.
#
# JetBrains builds expire about a month after release and old downloads are
# deleted, so the pin lives in `pin.json`, which `update.sh`
# (`just update-kotlin-lsp`) rewrites. The release date is passed through so the
# dev shell can say how old the pinned build is.
{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  unzip,
  autoPatchelfHook,
  zlib,
}:
let
  pin = lib.importJSON ./pin.json;
  inherit (pin) version;

  # Linux ships as a tarball, macOS as a zip with a `.sit` extension.
  system = stdenvNoCC.hostPlatform.system;
  file =
    {
      x86_64-linux = "kotlin-server-${version}.tar.gz";
      aarch64-linux = "kotlin-server-${version}-aarch64.tar.gz";
      aarch64-darwin = "kotlin-server-${version}-aarch64.sit";
    }
    .${system};
in
stdenvNoCC.mkDerivation {
  pname = "kotlin-lsp";
  inherit version;

  src = fetchurl {
    url = "https://download.jetbrains.com/language-server/kotlin-server/${version}/${file}";
    hash = pin.hashes.${system};
  };

  sourceRoot = "kotlin-server-${version}";

  # The macOS release is a zip with a `.sit` extension, which the default
  # unpacker does not recognise.
  unpackCmd = lib.optionalString stdenvNoCC.hostPlatform.isDarwin "unzip -q $curSrc";

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isDarwin [ unzip ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    zlib
  ];

  # The bundled runtime ships AWT, sound and font libraries that a headless
  # language server never loads.
  autoPatchelfIgnoreMissingDeps = [
    "libX*"
    "libxkbcommon*"
    "libwayland*"
    "libasound.so.2"
    "libfreetype.so.6"
    "libfontconfig.so.1"
    "libGL.so.1"
    "libEGL.so.1"
  ];

  installPhase = ''
    mkdir -p $out/share/kotlin-lsp $out/bin
    cp -r ./. $out/share/kotlin-lsp/
    makeWrapper $out/share/kotlin-lsp/bin/intellij-server $out/bin/kotlin-lsp
  '';

  passthru = {
    inherit (pin) released releasedEpoch;
  };

  # The source is Apache 2.0, but the release bundles closed-source JetBrains
  # components, so the binary is unfree; `flake.nix` allows this package by
  # name.
  meta = {
    description = "JetBrains' official Kotlin language server";
    homepage = "https://github.com/Kotlin/kotlin-lsp";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    mainProgram = "kotlin-lsp";
  };
}
