# Spec for CyShell for OpenSUSE/OBS

%global debug_package %{nil}

Name:           cyshell
Version:        1.2.3
Release:        1%{?dist}
Provides:        dms
Obsoletes:       dms
Summary:        CyShell - Labwc desktop shell for Wayland

License:        MIT
URL:            https://github.com/Cytech-Team/CyShell-Desktop
Source0:        cyshell-source.tar.gz
Source1:        cyshell-distropkg-amd64.gz
Source2:        cyshell-distropkg-arm64.gz

BuildRequires:  gzip
BuildRequires:  systemd-rpm-macros

# Core requirements
Requires:       (quickshell or quickshell-git)
Requires:       accountsservice
Requires:       dgop

# Core utilities (Highly recommended for CyShell functionality)
Recommends:     cava
Recommends:     danksearch
Recommends:     matugen
Recommends:     NetworkManager
Recommends:     qt6-multimedia-imports
Suggests:       cups-pk-helper
Suggests:       qt6ct

%description
CyShell is a modern Wayland desktop shell built with Quickshell
built specifically for the Labwc compositor. Features
notifications, app launcher, wallpaper customization, and plugin system.

Includes auto-theming for GTK/Qt apps with matugen, 20+ customizable widgets,
process monitoring, notification center, clipboard history, dock, control center,
lock screen, and comprehensive plugin system.

%prep
%setup -q -n CyShell-Desktop-%{version}

%ifarch x86_64
gunzip -c %{SOURCE1} > cyshell
%endif
%ifarch aarch64
gunzip -c %{SOURCE2} > cyshell
%endif
chmod +x cyshell

%build

%install
install -Dm755 cyshell %{buildroot}%{_bindir}/cyshell

install -d %{buildroot}%{_datadir}/bash-completion/completions
install -d %{buildroot}%{_datadir}/zsh/site-functions
install -d %{buildroot}%{_datadir}/fish/vendor_completions.d
./cyshell completion bash > %{buildroot}%{_datadir}/bash-completion/completions/cyshell || :
./cyshell completion zsh > %{buildroot}%{_datadir}/zsh/site-functions/_cyshell || :
./cyshell completion fish > %{buildroot}%{_datadir}/fish/vendor_completions.d/cyshell.fish || :

for unit in assets/systemd/cyshell*.service; do
    install -Dm644 "$unit" "%{buildroot}%{_userunitdir}/$(basename "$unit")"
done

install -Dm644 assets/cyshell-open.desktop %{buildroot}%{_datadir}/applications/cyshell-open.desktop
install -Dm644 assets/com.cytechteam.cyshell.desktop %{buildroot}%{_datadir}/applications/com.cytechteam.cyshell.desktop
install -Dm644 assets/com.cytechteam.cyshell.notepad.desktop %{buildroot}%{_datadir}/applications/com.cytechteam.cyshell.notepad.desktop
install -Dm644 assets/com.cytechteam.cyshell.png %{buildroot}%{_datadir}/icons/hicolor/512x512/apps/com.cytechteam.cyshell.png

install -dm755 %{buildroot}%{_datadir}/quickshell/cyshell
cp -r quickshell/* %{buildroot}%{_datadir}/quickshell/cyshell/
rm -rf %{buildroot}%{_datadir}/quickshell/cyshell/tests

rm -rf %{buildroot}%{_datadir}/quickshell/cyshell/.git*
rm -f %{buildroot}%{_datadir}/quickshell/cyshell/.gitignore
rm -rf %{buildroot}%{_datadir}/quickshell/cyshell/.github
rm -rf %{buildroot}%{_datadir}/quickshell/cyshell/distro
rm -rf %{buildroot}%{_datadir}/quickshell/cyshell/core

echo "%{version}" > %{buildroot}%{_datadir}/quickshell/cyshell/VERSION

%posttrans
# Signal running CyShell instances to reload
pkill -USR1 -x cyshell >/dev/null 2>&1 || :

%files
%license LICENSE
%doc CONTRIBUTING.md
%doc quickshell/README.md
%{_bindir}/cyshell
%dir %{_datadir}/fish
%dir %{_datadir}/fish/vendor_completions.d
%{_datadir}/fish/vendor_completions.d/cyshell.fish
%dir %{_datadir}/zsh
%dir %{_datadir}/zsh/site-functions
%{_datadir}/zsh/site-functions/_cyshell
%{_datadir}/bash-completion/completions/cyshell
%dir %{_datadir}/quickshell
%{_datadir}/quickshell/cyshell/
%{_userunitdir}/cyshell*.service
%{_datadir}/applications/cyshell-open.desktop
%{_datadir}/applications/com.cytechteam.cyshell.desktop
%{_datadir}/applications/com.cytechteam.cyshell.notepad.desktop
%dir %{_datadir}/icons/hicolor
%dir %{_datadir}/icons/hicolor/scalable
%dir %{_datadir}/icons/hicolor/scalable/apps
%{_datadir}/icons/hicolor/512x512/apps/com.cytechteam.cyshell.png

%changelog
* Mon Dec 16 2025 AvengeMedia <maintainer@avengemedia.com> - 1.0.3-1
- Update to stable v1.0.3 release

* Fri Dec 12 2025 AvengeMedia <maintainer@avengemedia.com> - 1.0.2-1
- Update to stable v1.0.2 release
- Bug fixes and improvements

* Fri Nov 22 2025 AvengeMedia <maintainer@avengemedia.com> - 0.6.2-1
- Stable release build with pre-built binaries
- Multi-arch support (x86_64, aarch64)
