# Root Makefile for CyShell Desktop
# Orchestrates building, installation, and systemd management

# Build configuration
BINARY_NAME=cyshell
PRIMARY_COMMAND=cyshell
CORE_DIR=core
BUILD_DIR=$(CORE_DIR)/bin
PREFIX ?= /usr/local
INSTALL_DIR=$(DESTDIR)$(PREFIX)/bin
DATA_DIR=$(DESTDIR)$(PREFIX)/share
LIB_DIR=$(DESTDIR)$(PREFIX)/lib/cyshell
WAYLAND_SESSION_DIR=$(DATA_DIR)/wayland-sessions
ICON_DIR=$(DATA_DIR)/icons/hicolor/512x512/apps
LABWC_BRIDGE_DIR=native/labwc-bridge

USER_HOME := $(if $(SUDO_USER),$(shell getent passwd $(SUDO_USER) | cut -d: -f6),$(HOME))
SYSTEMD_USER_DIR=$(USER_HOME)/.config/systemd/user
SYSTEMD_UNITS=cyshell.service cyshell-runtime-ui.service cyshell-shell-ui.service cyshell-settings-surface.service cyshell-panel.service cyshell-desktop.service cyshell-osd.service cyshell-ui-surfaces.service

SHELL_DIR=quickshell
QMLTESTRUNNER ?=
SHELL_INSTALL_DIR=$(DATA_DIR)/quickshell/cyshell
ASSETS_DIR=assets
APPLICATIONS_DIR=$(DATA_DIR)/applications

.PHONY: all build build-labwc-bridge dev run clean lint-qml install install-bin install-cystart-toggle install-labwc-bridge install-completions install-systemd install-icon install-desktop uninstall uninstall-bin uninstall-cystart-toggle uninstall-labwc-bridge uninstall-shell uninstall-completions uninstall-systemd uninstall-icon uninstall-desktop help

all: build

build:
	@echo "Building $(BINARY_NAME)..."
	@$(MAKE) -C $(CORE_DIR) build
	@$(MAKE) -C $(LABWC_BRIDGE_DIR)
	@echo "Build complete"

build-labwc-bridge:
	@echo "Building CyShell LabWC bridge..."
	@$(MAKE) -C $(LABWC_BRIDGE_DIR)

dev:
	@$(MAKE) -C $(CORE_DIR) dev

run: dev
	@$(BUILD_DIR)/$(BINARY_NAME) run -c $(CURDIR)/$(SHELL_DIR)

clean:
	@echo "Cleaning build artifacts..."
	@$(MAKE) -C $(CORE_DIR) clean
	@$(MAKE) -C $(LABWC_BRIDGE_DIR) clean
	@echo "Clean complete"

lint-qml:
	@./quickshell/scripts/qmllint-entrypoints.sh

.PHONY: test-qml
test-qml:
	QMLTESTRUNNER="$(QMLTESTRUNNER)" python3 quickshell/tests/run-qml.py

# Pull the latest dank-qml-common and pin it everywhere it is consumed
# (submodule pointer + nix flake input). Commit both in one change.
update-common:
	git submodule update --remote --merge dank-qml-common
	nix --extra-experimental-features 'nix-command flakes' flake update dank-qml-common

# Installation targets
install-bin:
	@echo "Installing CyShell to $(INSTALL_DIR)..."
	@install -D -m 755 $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(PRIMARY_COMMAND)
	@install -D -m 755 scripts/cyshell-language $(INSTALL_DIR)/cyshell-language
	@install -D -m 755 scripts/cyshell-end-task $(INSTALL_DIR)/cyshell-end-task
	@install -D -m 755 scripts/cyshell-theme-sync $(INSTALL_DIR)/cyshell-theme-sync
	@ln -sfn $(PRIMARY_COMMAND) $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "CyShell installed"

install-cystart-toggle:
	@echo "Installing the per-user CyStart keybind helper..."
	@install -D -m 755 scripts/cyshell-cystart-toggle $(USER_HOME)/.local/bin/cyshell-cystart-toggle
	@if [ -n "$(SUDO_USER)" ]; then chown "$(SUDO_USER):$$(id -gn "$(SUDO_USER)")" "$(USER_HOME)/.local/bin/cyshell-cystart-toggle"; fi
	@echo "CyStart keybind helper installed"

install-labwc-bridge: build-labwc-bridge
	@echo "Installing CyShell LabWC in-process bridge..."
	@install -D -m 755 $(LABWC_BRIDGE_DIR)/libcyshell-labwc-bridge.so $(LIB_DIR)/libcyshell-labwc-bridge.so
	@install -D -m 644 $(LABWC_BRIDGE_DIR)/compatibility.conf $(LIB_DIR)/compatibility.conf
	@install -D -m 755 scripts/cyshell-labwc-session $(INSTALL_DIR)/cyshell-labwc-session
	@install -D -m 644 $(ASSETS_DIR)/cyshell-labwc.desktop $(WAYLAND_SESSION_DIR)/labwc.desktop
	@echo "LabWC bridge installed"

install-completions:
	@echo "Installing shell completions..."
	@mkdir -p $(DATA_DIR)/bash-completion/completions
	@mkdir -p $(DATA_DIR)/zsh/site-functions
	@mkdir -p $(DATA_DIR)/fish/vendor_completions.d
	@$(BUILD_DIR)/$(BINARY_NAME) completion bash > $(DATA_DIR)/bash-completion/completions/cyshell 2>/dev/null || true
	@$(BUILD_DIR)/$(BINARY_NAME) completion zsh > $(DATA_DIR)/zsh/site-functions/_cyshell 2>/dev/null || true
	@$(BUILD_DIR)/$(BINARY_NAME) completion fish > $(DATA_DIR)/fish/vendor_completions.d/cyshell.fish 2>/dev/null || true
	@echo "Shell completions installed"

install-systemd:
ifneq ($(shell uname),Linux)
	@echo "Skipping systemd user service (non-Linux); start the shell from your compositor config with 'cyshell run'"
else
	@echo "Installing systemd user service..."
	@mkdir -p $(SYSTEMD_USER_DIR)
	@if [ -n "$(SUDO_USER)" ]; then chown -R $(SUDO_USER):"$(id -gn $SUDO_USER)" $(SYSTEMD_USER_DIR); fi
	@for unit in $(SYSTEMD_UNITS); do sed 's|/usr/bin/cyshell|$(PREFIX)/bin/cyshell|g' $(ASSETS_DIR)/systemd/$$unit > $(SYSTEMD_USER_DIR)/$$unit; chmod 644 $(SYSTEMD_USER_DIR)/$$unit; done
	@if [ -n "$(SUDO_USER)" ]; then for unit in $(SYSTEMD_UNITS); do chown $(SUDO_USER):"$(id -gn $SUDO_USER)" $(SYSTEMD_USER_DIR)/$$unit; done; fi
	@echo "Systemd services installed to $(SYSTEMD_USER_DIR)"
endif

install-icon:
	@echo "Installing icon..."
	@install -D -m 644 $(ASSETS_DIR)/com.cytechteam.cyshell.png $(ICON_DIR)/com.cytechteam.cyshell.png
	@gtk-update-icon-cache -q $(DATA_DIR)/icons/hicolor 2>/dev/null || true
	@echo "Icon installed"

install-desktop:
	@echo "Installing desktop entries..."
	@install -D -m 644 $(ASSETS_DIR)/cyshell-open.desktop $(APPLICATIONS_DIR)/cyshell-open.desktop
	@install -D -m 644 $(ASSETS_DIR)/com.cytechteam.cyshell.desktop $(APPLICATIONS_DIR)/com.cytechteam.cyshell.desktop
	@install -D -m 644 $(ASSETS_DIR)/com.cytechteam.cyshell.notepad.desktop $(APPLICATIONS_DIR)/com.cytechteam.cyshell.notepad.desktop
	@update-desktop-database -q $(APPLICATIONS_DIR) 2>/dev/null || true
	@echo "Desktop entries installed"

install: install-bin install-cystart-toggle install-labwc-bridge install-completions install-systemd install-icon install-desktop
	@echo ""
	@echo "Installation complete!"
	@echo ""
	@echo "=== CyShell Desktop installed ==="

# Uninstallation targets
uninstall-bin:
	@echo "Removing $(BINARY_NAME) from $(INSTALL_DIR)..."
	@rm -f $(INSTALL_DIR)/$(BINARY_NAME)
	@rm -f $(INSTALL_DIR)/cyshell-language
	@rm -f $(INSTALL_DIR)/cyshell-end-task
	@rm -f $(INSTALL_DIR)/cyshell-theme-sync
	@echo "Binary removed"

uninstall-cystart-toggle:
	@echo "Removing the per-user CyStart keybind helper..."
	@rm -f $(USER_HOME)/.local/bin/cyshell-cystart-toggle
	@echo "CyStart keybind helper removed"

uninstall-labwc-bridge:
	@echo "Removing CyShell LabWC bridge..."
	@rm -f $(LIB_DIR)/libcyshell-labwc-bridge.so
	@rm -f $(LIB_DIR)/compatibility.conf
	@rm -f $(INSTALL_DIR)/cyshell-labwc-session
	@rm -f $(WAYLAND_SESSION_DIR)/labwc.desktop
	@echo "LabWC bridge removed"

uninstall-shell:
	@echo "Removing pre-1.6 shell files from $(SHELL_INSTALL_DIR)..."
	@rm -rf $(SHELL_INSTALL_DIR)
	@echo "Shell files removed"

uninstall-completions:
	@echo "Removing shell completions..."
	@rm -f $(DATA_DIR)/bash-completion/completions/cyshell
	@rm -f $(DATA_DIR)/zsh/site-functions/_cyshell
	@rm -f $(DATA_DIR)/fish/vendor_completions.d/cyshell.fish
	@echo "Shell completions removed"

uninstall-systemd:
	@echo "Removing systemd user service..."
	@for unit in $(SYSTEMD_UNITS); do rm -f $(SYSTEMD_USER_DIR)/$$unit; done
	@echo "Systemd service removed"
	@echo "Note: Stop/disable service manually if running: systemctl --user stop cyshell"

uninstall-icon:
	@echo "Removing icon..."
	@rm -f $(ICON_DIR)/com.cytechteam.cyshell.png
	@rm -f $(DATA_DIR)/icons/hicolor/scalable/apps/danklogo.svg
	@gtk-update-icon-cache -q $(DATA_DIR)/icons/hicolor 2>/dev/null || true
	@echo "Icon removed"

uninstall-desktop:
	@echo "Removing desktop entries..."
	@rm -f $(APPLICATIONS_DIR)/cyshell-open.desktop
	@rm -f $(APPLICATIONS_DIR)/com.cytechteam.cyshell.desktop
	@rm -f $(APPLICATIONS_DIR)/com.cytechteam.cyshell.notepad.desktop
	@update-desktop-database -q $(APPLICATIONS_DIR) 2>/dev/null || true
	@echo "Desktop entries removed"

uninstall: uninstall-systemd uninstall-desktop uninstall-icon uninstall-completions uninstall-labwc-bridge uninstall-cystart-toggle uninstall-shell uninstall-bin
	@echo ""
	@echo "Uninstallation complete!"

# Target assist
help:
	@echo "Available targets:"
	@echo ""
	@echo "Build:"
	@echo "  all (default)        - Build the CyShell backend binary"
	@echo "  build                - Build backend + LabWC bridge"
	@echo "  build-labwc-bridge   - Build only the LabWC in-process bridge"
	@echo "  clean                - Clean build artifacts"
	@echo "  lint-qml             - Run qmllint on shell entrypoints using the Quickshell tooling VFS"
	@echo "  test-qml             - Run shell logic, Qt unit tests and QML widget regressions"
	@echo ""
	@echo "Install:"
	@echo "  install              - Build and install everything (requires sudo)"
	@echo "  install-bin          - Install only the binary"
	@echo "  install-labwc-bridge - Install LabWC bridge + session wrapper"
	@echo "  install-completions  - Install only shell completions"
	@echo "  install-systemd      - Install only systemd service"
	@echo "  install-icon         - Install only icon"
	@echo "  install-desktop      - Install only desktop entry"
	@echo ""
	@echo "Uninstall:"
	@echo "  uninstall            - Remove everything (requires sudo)"
	@echo "  uninstall-bin        - Remove only the binary"
	@echo "  uninstall-shell      - Remove shell files left by pre-1.6 installs"
	@echo "  uninstall-completions - Remove only shell completions"
	@echo "  uninstall-systemd    - Remove only systemd service"
	@echo "  uninstall-icon       - Remove only icon"
	@echo "  uninstall-desktop    - Remove only desktop entry"
	@echo ""
	@echo "Usage:"
	@echo "  sudo make install              - Build and install CyShell"
	@echo "  sudo make uninstall            - Remove CyShell"
	@echo "  systemctl --user enable --now cyshell  - Enable and start service"
