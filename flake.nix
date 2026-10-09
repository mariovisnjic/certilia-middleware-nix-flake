{
  description = "Certilia/AKD middleware for the Croatian eID card, packaged as a Nix flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        version = "3.9.12-1";

        sources = {
          "x86_64-linux" = {
            arch = "amd64";
            hash = "sha256-h34ddSfavOkg6MfoVEWTCzlyGu3VcJ8tHPa/Ep7NolM=";
          };
        };

        src = sources.${system} or (throw "unsupported system: ${system}");

        # The .deb ships an FHS interpreter (/lib64/ld-linux-x86-64.so.2) and
        # bundles its own Qt6, so autoPatchelfHook rewrites the interpreter +
        # rpaths, and a wrapper points Qt at the bundled libs/plugins and forces
        # the xcb platform (no wayland plugin is bundled -> runs via XWayland).
        certilia-middleware = pkgs.stdenv.mkDerivation (finalAttrs: {
          pname = "certilia-middleware";
          inherit version;

          src = pkgs.fetchurl {
            url = "https://repo.certilia.com/repository/debian/pool/c/certiliamiddleware/certiliamiddleware_${version}_${src.arch}.deb";
            inherit (src) hash;
          };

          nativeBuildInputs = with pkgs; [
            dpkg
            autoPatchelfHook
            makeWrapper
          ];

          buildInputs = with pkgs; [
            stdenv.cc.cc.lib
            pcsclite
            glib
            dbus
            zlib
            fontconfig
            freetype
            libGL
            libxkbcommon
            libjpeg8     # libjpeg.so.8 for the bundled JPEG2000 image plugin
            cups         # libcups.so.2 for the bundled print-support plugin
            xcb-util-cursor
            # The xorg.* package set is deprecated; these are now top-level.
            # Hyphenated names can't be bare under `with pkgs` (parsed as
            # subtraction), so they're accessed explicitly.
            libx11
            libxext
            libxrender
            libxcb
            pkgs."libxcb-util"
            pkgs."libxcb-image"
            pkgs."libxcb-keysyms"
            pkgs."libxcb-render-util"
            pkgs."libxcb-wm"
          ];

          unpackPhase = ''
            runHook preUnpack
            dpkg-deb -x $src .
            runHook postUnpack
          '';
          sourceRoot = ".";

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -r opt $out/
            install -Dm644 usr/share/pixmaps/certiliaicon.png \
              $out/share/pixmaps/certiliaicon.png
            runHook postInstall
          '';

          # Wrap the Qt executables: bundled libs on LD_LIBRARY_PATH, bundled Qt
          # plugins via QT_PLUGIN_PATH, force xcb (only platform plugin shipped).
          postFixup = ''
            base=$out/opt/certiliamiddleware
            for app in CertiliaClient CertiliaSigner; do
              makeWrapper $base/$app $out/bin/$app \
                --set QT_QPA_PLATFORM xcb \
                --set QT_PLUGIN_PATH $base/plugins \
                --prefix LD_LIBRARY_PATH : $base/lib
            done

            mkdir -p $out/share/applications
            for app in certiliaclient certiliasigner; do
              desktop=usr/share/applications/$app.desktop
              bin=$(grep -oP '(?<=/opt/certiliamiddleware/)\w+' $desktop | head -n1)
              substitute $desktop $out/share/applications/$app.desktop \
                --replace "/opt/certiliamiddleware/$bin" "$out/bin/$bin" \
                --replace "Icon=certiliaicon.png" "Icon=$out/share/pixmaps/certiliaicon.png"
            done
          '';

          # Path to the PKCS#11 module, for wiring into Firefox/Chrome.
          passthru.pkcs11Module =
            "${finalAttrs.finalPackage}/opt/certiliamiddleware/pkcs11/libCertiliaPkcs11.so";

          meta = with pkgs.lib; {
            description = "Certilia/AKD middleware for the Croatian eID card (PKCS#11, signer, client)";
            homepage = "http://www.certilia.com/";
            license = licenses.unfree;
            platforms = builtins.attrNames sources;
            sourceProvenance = with sourceTypes; [ binaryNativeCode ];
          };
        });
      in {
        packages.default = certilia-middleware;
        packages.certilia-middleware = certilia-middleware;

        apps.client = {
          type = "app";
          program = "${certilia-middleware}/bin/CertiliaClient";
        };
        apps.signer = {
          type = "app";
          program = "${certilia-middleware}/bin/CertiliaSigner";
        };
        apps.default = self.apps.${system}.client;
      });
}
