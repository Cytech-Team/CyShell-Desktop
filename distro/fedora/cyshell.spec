# Feodra spec for CyShell stable releases

%global debug_package %{nil}
%global version VERSION_PLACEHOLDER
%global pkg_summary CyShell - Labwc desktop shell for Wayland

Name:           cyshell
Version:        %{version}
Release:        RELEASE_PLACEHOLDER%{?dist}
Provides:        dms
Obsoletes:       dms
Summary:        %{pkg_summary}

License:        MIT
URL:            https://github.com/Cytech-Team/CyShell-Desktop

Source0:        cyshell-qml.tar.gz

BuildRequires:  gzip
BuildRequires:  wget
BuildRequires:  systemd-rpm-macros

Requires:       (quickshell or quickshell-git)
Requires:       accountsservice
Requires:       cyshell-cli = %{version}-%{release}
Requires:       dgop

Recommends:     cava
Recommends:     danksearch
Recommends:     matugen
Recommends:     NetworkManager
Recommends:     qt6-qtmultimedia
Suggests:       cups-pk-helper
Suggests:       qt6ct

%description
CyShell is a modern Wayland desktop shell built with Quickshell
built specifically for the Labwc compositor. Features notifications,
app launcher, wallpaper customization, and fully customizable with plugins.

Includes auto-theming for GTK/Qt apps with matugen, 20+ customizable widgets,
process monitoring, notification center, clipboard history, dock, control center,
lock screen, and comprehensive plugin system.

%package -n cyshell-cli
Summary:        CyShell CLI tool
License:        MIT
URL:            https://github.com/Cytech-Team/CyShell-Desktop

%description -n cyshell-cli
Command-line interface for CyShell configuration and management.
Provides native DBus bindings, NetworkManager integration, and system utilities.

%prep
%setup -q -c -n cyshell-qml

case "%{_arch}" in
  x86_64)
    ARCH_SUFFIX="amd64"
    ;;
  aarch64)
    ARCH_SUFFIX="arm64"
    ;;
  *)
    echo "Unsupported architecture: %{_arch}"
    exit 1
    ;;
esac

# Download cyshell-cli for target architecture
wget -O %{_builddir}/cyshell-cli.gz "https://github.com/Cytech-Team/CyShell-Desktop/releases/latest/download/cyshell-distropkg-${ARCH_SUFFIX}.gz" || {
  echo "Failed to download cyshell-cli for architecture %{_arch}"
  exit 1
}
gunzip -c %{_builddir}/cyshell-cli.gz > %{_builddir}/cyshell-cli
chmod +x %{_builddir}/cyshell-cli

%build

%install
install -Dm755 %{_builddir}/cyshell-cli %{buildroot}%{_bindir}/cyshell

# Shell completions
install -d %{buildroot}%{_datadir}/bash-completion/completions
install -d %{buildroot}%{_datadir}/zsh/site-functions
install -d %{buildroot}%{_datadir}/fish/vendor_completions.d
%{_builddir}/cyshell-cli completion bash > %{buildroot}%{_datadir}/bash-completion/completions/cyshell || :
%{_builddir}/cyshell-cli completion zsh > %{buildroot}%{_datadir}/zsh/site-functions/_cyshell || :
%{_builddir}/cyshell-cli completion fish > %{buildroot}%{_datadir}/fish/vendor_completions.d/cyshell.fish || :

for unit in %{_builddir}/cyshell-qml/assets/systemd/cyshell*.service; do
    install -Dm644 "$unit" "%{buildroot}%{_userunitdir}/$(basename "$unit")"
done

install -Dm644 %{_builddir}/cyshell-qml/assets/cyshell-open.desktop %{buildroot}%{_datadir}/applications/cyshell-open.desktop
install -Dm644 %{_builddir}/cyshell-qml/assets/com.cytechteam.cyshell.desktop %{buildroot}%{_datadir}/applications/com.cytechteam.cyshell.desktop
install -Dm644 %{_builddir}/cyshell-qml/assets/com.cytechteam.cyshell.notepad.desktop %{buildroot}%{_datadir}/applications/com.cytechteam.cyshell.notepad.desktop
install -Dm644 %{_builddir}/cyshell-qml/assets/com.cytechteam.cyshell.png %{buildroot}%{_datadir}/icons/hicolor/512x512/apps/com.cytechteam.cyshell.png

install -dm755 %{buildroot}%{_datadir}/quickshell/cyshell
cp -r %{_builddir}/cyshell-qml/* %{buildroot}%{_datadir}/quickshell/cyshell/

rm -rf %{buildroot}%{_datadir}/quickshell/cyshell/.git*
rm -f %{buildroot}%{_datadir}/quickshell/cyshell/.gitignore
rm -rf %{buildroot}%{_datadir}/quickshell/cyshell/.github
rm -rf %{buildroot}%{_datadir}/quickshell/cyshell/distro

echo "%{version}" > %{buildroot}%{_datadir}/quickshell/cyshell/VERSION

%posttrans
# Signal running CyShell instances to reload
pkill -USR1 -x cyshell >/dev/null 2>&1 || :

%files
%license LICENSE
%doc README.md CONTRIBUTING.md
%{_datadir}/quickshell/cyshell/
%{_userunitdir}/cyshell*.service
%{_datadir}/applications/cyshell-open.desktop
%{_datadir}/applications/com.cytechteam.cyshell.desktop
%{_datadir}/applications/com.cytechteam.cyshell.notepad.desktop
%{_datadir}/icons/hicolor/512x512/apps/com.cytechteam.cyshell.png

%files -n cyshell-cli
%{_bindir}/cyshell
%{_datadir}/bash-completion/completions/cyshell
%{_datadir}/zsh/site-functions/_cyshell
%{_datadir}/fish/vendor_completions.d/cyshell.fish

%changelog
* CHANGELOG_DATE_PLACEHOLDER AvengeMedia <contact@avengemedia.com> - VERSION_PLACEHOLDER-RELEASE_PLACEHOLDER
- Stable release VERSION_PLACEHOLDER
- Built from GitHub release
