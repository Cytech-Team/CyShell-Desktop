# Spec for CyShell - uses rpkg macros for git builds

%global debug_package %{nil}
%global version {{{
set -e
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
    git fetch --unshallow --quiet
fi
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
    echo "clone is still shallow; refusing a truncated commit count" >&2
    exit 1
fi
printf '0.0.git.%s.%s\n' \
    "$(git rev-list --count HEAD)" \
    "$(git rev-parse --short=8 HEAD)"
}}}
%global pkg_summary CyShell - Labwc desktop shell for Wayland
%global go_toolchain_version 1.26.5

Name:           cyshell
Epoch:          2
Version:        %{version}
Release:        1%{?dist}
Provides:        dms
Obsoletes:       dms < %{epoch}:%{version}-%{release}
Summary:        %{pkg_summary}

License:        MIT
URL:            https://github.com/Cytech-Team/CyShell-Desktop
VCS:            {{{ git_repo_vcs }}}
Source0:        {{{ git_repo_pack }}}
Source1:        https://go.dev/dl/go%{go_toolchain_version}.linux-amd64.tar.gz
Source2:        https://go.dev/dl/go%{go_toolchain_version}.linux-arm64.tar.gz
# git_repo_pack archives skip submodule content, so pack dank-qml-common separately
Source3:        {{{ git_pack path=$GIT_ROOT/dank-qml-common dir_name=dank-qml-common source_name=dank-qml-common.tar.gz }}}

BuildRequires:  git-core
BuildRequires:  gzip
BuildRequires:  make
BuildRequires:  systemd-rpm-macros

# Core requirements
Requires:       (quickshell-git or quickshell)
Requires:       accountsservice
Requires:       cyshell-cli = %{epoch}:%{version}-%{release}

# Core utilities (Recommended for CyShell functionality)
Recommends:     cava
Recommends:     danksearch
Recommends:     matugen
Recommends:     quickshell-git

# Recommended system packages
Recommends:     NetworkManager
Recommends:     qt6-qtmultimedia
Suggests:       cups-pk-helper
Suggests:       qt6ct

%description
CyShell is a modern Wayland desktop shell built with Quickshell
and built specifically for Labwc. Features notifications,
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
{{{ git_repo_setup_macro }}}
rm -rf dank-qml-common
tar -xzf %{SOURCE3}
test -e quickshell/DankCommon/Widgets/CyIcon.qml || { echo "CyShell Common CyIcon.qml missing after submodule unpack"; exit 1; }

%build
# Build CyShell CLI from source (core/subdirectory)
VERSION="%{version}"
COMMIT=$(echo "%{version}" | grep -oP '[a-f0-9]{7,}' | head -n1 || echo "unknown")

# Use pinned bundled Go toolchain (deterministic across chroots)
case "%{_arch}" in
  x86_64)
    GO_TARBALL="%{_sourcedir}/go%{go_toolchain_version}.linux-amd64.tar.gz"
    ;;
  aarch64)
    GO_TARBALL="%{_sourcedir}/go%{go_toolchain_version}.linux-arm64.tar.gz"
    ;;
  *)
    echo "Unsupported architecture for bundled Go: %{_arch}"
    exit 1
    ;;
esac

rm -rf .go
tar -xzf "$GO_TARBALL"
mv go .go
export GOROOT="$PWD/.go"
export PATH="$GOROOT/bin:$PATH"
export GOTOOLCHAIN=local
go version

cd core
make dist VERSION="$VERSION" COMMIT="$COMMIT"

%install
# Install cyshell-cli binary (built from source)
case "%{_arch}" in
  x86_64)
    CYSHELL_BINARY="cyshell-linux-amd64"
    ;;
  aarch64)
    CYSHELL_BINARY="cyshell-linux-arm64"
    ;;
  *)
    echo "Unsupported architecture: %{_arch}"
    exit 1
    ;;
esac

install -Dm755 core/bin/${CYSHELL_BINARY} %{buildroot}%{_bindir}/cyshell

# Shell completions
install -d %{buildroot}%{_datadir}/bash-completion/completions
install -d %{buildroot}%{_datadir}/zsh/site-functions
install -d %{buildroot}%{_datadir}/fish/vendor_completions.d
core/bin/${CYSHELL_BINARY} completion bash > %{buildroot}%{_datadir}/bash-completion/completions/cyshell || :
core/bin/${CYSHELL_BINARY} completion zsh > %{buildroot}%{_datadir}/zsh/site-functions/_cyshell || :
core/bin/${CYSHELL_BINARY} completion fish > %{buildroot}%{_datadir}/fish/vendor_completions.d/cyshell.fish || :

# Install systemd user service
for unit in assets/systemd/cyshell*.service; do
    install -Dm644 "$unit" "%{buildroot}%{_userunitdir}/$(basename "$unit")"
done

install -Dm644 assets/cyshell-open.desktop %{buildroot}%{_datadir}/applications/cyshell-open.desktop
install -Dm644 assets/com.cytechteam.cyshell.desktop %{buildroot}%{_datadir}/applications/com.cytechteam.cyshell.desktop
install -Dm644 assets/com.cytechteam.cyshell.notepad.desktop %{buildroot}%{_datadir}/applications/com.cytechteam.cyshell.notepad.desktop
install -Dm644 assets/com.cytechteam.cyshell.png %{buildroot}%{_datadir}/icons/hicolor/512x512/apps/com.cytechteam.cyshell.png

%posttrans
# Signal running CyShell instances to reload
pkill -USR1 -x cyshell >/dev/null 2>&1 || :

%files
%license LICENSE
%doc CONTRIBUTING.md
%doc quickshell/README.md
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
{{{ git_repo_changelog }}}
