{
  description = "CyShell Desktop";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
    dank-qml-common = {
      url = "github:AvengeMedia/dank-qml-common";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      dank-qml-common,
      ...
    }:
    let
      goModVersion =
        let
          content = builtins.readFile ./core/go.mod;
          lines = builtins.filter builtins.isString (builtins.split "\n" content);
          goLines = builtins.filter (l: builtins.match "go [0-9]+\\..*" l != null) lines;
          matched =
            if goLines != [ ] then builtins.match "go ([0-9]+)\\.([0-9]+).*" (builtins.head goLines) else null;
        in
        if matched != null then
          {
            major = builtins.elemAt matched 0;
            minor = builtins.elemAt matched 1;
          }
        else
          {
            major = "1";
            minor = "25";
          };
      goForPkgs = pkgs: pkgs.${"go_${goModVersion.major}_${goModVersion.minor}"};
      forEachSystem =
        fn:
        nixpkgs.lib.genAttrs [ "aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux" ] (
          system: fn system nixpkgs.legacyPackages.${system}
        );
      forEachLinuxSystem =
        fn:
        nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
          system: fn system nixpkgs.legacyPackages.${system}
        );

      mkModuleWithCyShellPkgs =
        modulePath:
        args@{ pkgs, ... }:
        {
          imports = [
            (import modulePath (args // { cyShellPkgs = buildCyShellPkgs pkgs; }))
          ];
        };

      mkQmlImportPath =
        pkgs: qmlPkgs:
        pkgs.lib.concatStringsSep ":" (map (o: "${o}/${pkgs.qt6.qtbase.qtQmlPrefix}") qmlPkgs);

      mkQtPluginPath =
        pkgs: qtPkgs:
        pkgs.lib.concatStringsSep ":" (map (o: "${o}/${pkgs.qt6.qtbase.qtPluginPrefix}") qtPkgs);

      qmlPkgs =
        pkgs: with pkgs.kdePackages; [
          kirigami.unwrapped
          sonnet
          qtmultimedia
          qtimageformats
          kimageformats
        ];

      # Allows downstream modules to provide their own 'pkgs' (with overlays)
      # instead of being forced to use the flake's locked nixpkgs.
      mkCyShell =
        pkgs:
        let
          mkDate =
            longDate:
            pkgs.lib.concatStringsSep "-" [
              (builtins.substring 0 4 longDate)
              (builtins.substring 4 2 longDate)
              (builtins.substring 6 2 longDate)
            ];
          version =
            let
              rawVersion = pkgs.lib.removePrefix "v" (pkgs.lib.trim (builtins.readFile ./quickshell/VERSION));
              cleanVersion = builtins.replaceStrings [ " " ] [ "" ] rawVersion;
              dateSuffix = "+date=" + mkDate (self.lastModifiedDate or "19700101");
              revSuffix = "_" + (self.shortRev or "dirty");
            in
            "${cleanVersion}${dateSuffix}${revSuffix}";
        in
        pkgs.lib.makeOverridable (
          {
            extraQtPackages ? [ ],
          }:
          (pkgs.buildGoModule.override { go = goForPkgs pkgs; }) (
            let
              rootSrc = ./.;
              qtPackages = (qmlPkgs pkgs) ++ extraQtPackages;
            in
            {
              inherit version;
              pname = "cyshell";
              src = ./core;
              vendorHash = "sha256-eZBP7+9NLdJ88qizCZ+mTmcQO+FHthqQSmNtUErfKv4=";

              subPackages = [ "cmd/cyshell" ];

              ldflags = [
                "-s"
                "-w"
                "-X 'main.Version=${version}'"
              ];

              nativeBuildInputs = with pkgs; [
                installShellFiles
                makeWrapper
              ];

              postInstall = ''
                mkdir -p $out/share/quickshell/cyshell
                tar -C ${rootSrc}/quickshell --mode=u+w --exclude-from=${rootSrc}/scripts/shell-test-excludes.txt -cf - . \
                  | tar -C $out/share/quickshell/cyshell -xf -

                rm -f $out/share/quickshell/cyshell/CyCommon $out/share/quickshell/cyshell/DankCommon
                tar -C ${dank-qml-common} --mode=u+w --exclude-from=${rootSrc}/scripts/shell-test-excludes.txt -cf - CyCommon \
                  | tar -C $out/share/quickshell/cyshell -xf -
                ln -s CyCommon $out/share/quickshell/cyshell/DankCommon

                echo "${version}" > $out/share/quickshell/cyshell/VERSION

                # Install desktop file and icon
                install -D ${rootSrc}/assets/cyshell-open.desktop \
                  $out/share/applications/cyshell-open.desktop
                install -D ${rootSrc}/assets/com.cytechteam.cyshell.desktop \
                  $out/share/applications/com.cytechteam.cyshell.desktop
                install -D ${rootSrc}/assets/com.cytechteam.cyshell.notepad.desktop \
                  $out/share/applications/com.cytechteam.cyshell.notepad.desktop
                install -D ${rootSrc}/assets/com.cytechteam.cyshell.png \
                  $out/share/icons/hicolor/512x512/apps/com.cytechteam.cyshell.png

                # Snapshot pre-wrap Qt paths so launched apps get their own, not DMS's pins.
                wrapProgram $out/bin/cyshell \
                  --add-flags "-c $out/share/quickshell/cyshell" \
                  --run 'export CYSHELL_ORIG_NIXPKGS_QT6_QML_IMPORT_PATH="''${NIXPKGS_QT6_QML_IMPORT_PATH:-}"' \
                  --run 'export CYSHELL_ORIG_QT_PLUGIN_PATH="''${QT_PLUGIN_PATH:-}"' \
                  --prefix "NIXPKGS_QT6_QML_IMPORT_PATH" ":" "${mkQmlImportPath pkgs qtPackages}" \
                  --prefix "QT_PLUGIN_PATH" ":" "${mkQtPluginPath pkgs qtPackages}"

                mkdir -p $out/lib/systemd/user
                for unit in ${rootSrc}/assets/systemd/cyshell*.service; do
                  name="$(basename "$unit")"
                  install -Dm644 "$unit" "$out/lib/systemd/user/$name"
                  substituteInPlace "$out/lib/systemd/user/$name" \
                    --replace-fail /usr/bin/cyshell $out/bin/cyshell
                done

                substituteInPlace $out/share/quickshell/cyshell/assets/pam/fprint \
                  --replace-fail pam_fprintd.so ${pkgs.fprintd}/lib/security/pam_fprintd.so \
                  --replace-fail pam_deny.so ${pkgs.pam}/lib/security/pam_deny.so \
                  --replace-fail pam_permit.so ${pkgs.pam}/lib/security/pam_permit.so

                substituteInPlace $out/share/quickshell/cyshell/assets/pam/u2f \
                  --replace-fail pam_u2f.so ${pkgs.pam_u2f}/lib/security/pam_u2f.so \
                  --replace-fail pam_deny.so ${pkgs.pam}/lib/security/pam_deny.so \
                  --replace-fail pam_permit.so ${pkgs.pam}/lib/security/pam_permit.so

                substituteInPlace $out/share/quickshell/cyshell/assets/pam/other \
                  --replace-fail pam_deny.so ${pkgs.pam}/lib/security/pam_deny.so

                installShellCompletion --cmd cyshell \
                  --bash <($out/bin/cyshell completion bash) \
                  --fish <($out/bin/cyshell completion fish) \
                  --zsh <($out/bin/cyshell completion zsh)
              '';

              meta = {
                description = "CyShell Desktop: Labwc desktop shell built with Quickshell and Go";
                homepage = "https://github.com/Cytech-Team/CyShell-Desktop";
                changelog = "https://github.com/Cytech-Team/CyShell-Desktop/releases/tag/v${version}";
                license = pkgs.lib.licenses.mit;
                mainProgram = "cyshell";
                platforms = pkgs.lib.platforms.linux;
              };
            }
          )
        ) { };

      buildCyShellPkgs = pkgs: {
        cyshell = mkCyShell pkgs;
        dms-shell = builtins.warn "CyShell: package name dms-shell is deprecated; use cyshell" (mkCyShell pkgs);
      };
    in
    {
      packages = forEachSystem (
        system: pkgs: {
          cyshell = mkCyShell pkgs;
          dms-shell = builtins.warn "CyShell: package name dms-shell is deprecated; use cyshell" self.packages.${system}.cyshell;
          default = self.packages.${system}.cyshell;
          quickshell = builtins.warn "CyShell does not bundle Quickshell as a separate package; use nixpkgs or the upstream Quickshell flake." pkgs.quickshell;
        }
      );

      lib = { inherit mkCyShell buildCyShellPkgs; };

      homeModules.cyshell = mkModuleWithCyShellPkgs ./distro/nix/home.nix;

      homeModules.default = self.homeModules.cyshell;

      homeModules.dank-material-shell = builtins.warn "CyShell: homeModules.dank-material-shell is deprecated; use homeModules.cyshell" self.homeModules.cyshell;
      homeModules.dankMaterialShell.default = builtins.warn "CyShell: homeModules.dankMaterialShell.default is deprecated; use homeModules.cyshell" self.homeModules.cyshell;

      # Kept only as a migration surface for old Niri configurations; CyShell itself targets Labwc.
      homeModules.niri = import ./distro/nix/niri.nix;
      homeModules.dankMaterialShell.niri = builtins.warn "CyShell: the legacy Niri module is compatibility-only" self.homeModules.niri;

      nixosModules.cyshell = mkModuleWithCyShellPkgs ./distro/nix/nixos.nix;
      nixosModules.default = self.nixosModules.cyshell;
      nixosModules.dank-material-shell = builtins.warn "CyShell: nixosModules.dank-material-shell is deprecated; use nixosModules.cyshell" self.nixosModules.cyshell;
      nixosModules.dankMaterialShell = builtins.warn "CyShell: nixosModules.dankMaterialShell is deprecated; use nixosModules.cyshell" self.nixosModules.cyshell;

      nixosModules.greeter = builtins.warn "CyShell Greeter is managed separately; the legacy dms-greeter integration remains external compatibility" { };

      devShells = forEachSystem (
        system: pkgs:
        let
          devQmlPkgs = with pkgs;
          [
            quickshell
            kdePackages.qtdeclarative
          ]
          ++ (qmlPkgs pkgs);
          # the surface fixtures run niri on winit/X11, which dlopens these
          niriForTests = pkgs.symlinkJoin {
            name = "niri-x11";
            paths = [ pkgs.niri ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/niri --prefix LD_LIBRARY_PATH : ${
                pkgs.lib.makeLibraryPath [
                  (pkgs.libx11 or pkgs.xorg.libX11)
                  (pkgs.libxcb or pkgs.xorg.libxcb)
                  (pkgs.libxcursor or pkgs.xorg.libXcursor)
                  (pkgs.libxi or pkgs.xorg.libXi)
                ]
              }
            '';
          };
        in
        {
          default = pkgs.mkShell {
            buildInputs =
              with pkgs;
              [
                (goForPkgs pkgs)
                go-mockery
                gopls
                delve
                go-tools
                gnumake
                nodejs
                (python3.withPackages (ps: [ ps.dbus-next ]))

                prek
                uv # for prek
                shellcheck

                # Nix development tools
                nixd
                nil
              ]
              ++ devQmlPkgs
              ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ niriForTests pkgs.xvfb pkgs.dbus ];

            shellHook = ''
              touch quickshell/.qmlls.ini 2>/dev/null
              if [ ! -f .git/hooks/pre-commit ]; then prek install; fi
            '';

            QML2_IMPORT_PATH = mkQmlImportPath pkgs devQmlPkgs;
            QT_PLUGIN_PATH = mkQtPluginPath pkgs devQmlPkgs;
          };
        }
      );

      nixosTests = forEachLinuxSystem (
        system: pkgs:
        import ./distro/nix/tests {
          inherit
            self
            pkgs
            ;
          lib = pkgs.lib;
        }
      );
    };
}
