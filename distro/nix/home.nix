{
  config,
  pkgs,
  lib,
  ...
}@args:
let
  cfg = config.programs.cyshell;
  jsonFormat = pkgs.formats.json { };
  common = import ./common.nix {
    inherit
      config
      pkgs
      lib
      ;
  };
  hasPluginSettings = lib.any (plugin: plugin.settings != { }) (
    lib.attrValues (lib.filterAttrs (n: v: v.enable) cfg.plugins)
  );
  pluginSettings = lib.mapAttrs (name: plugin: { enabled = plugin.enable; } // plugin.settings) (
    lib.filterAttrs (n: v: v.enable) cfg.plugins
  );
in
{
  imports = [
    (import ./options.nix args)
    (lib.mkRemovedOptionModule [
      "programs"
      "cyshell"
      "enableNightMode"
    ] "Night mode is now always available")
    (lib.mkRemovedOptionModule [
      "programs"
      "cyshell"
      "default"
      "settings"
    ] "Default settings have been removed and been replaced with programs.cyshell.settings")
    (lib.mkRemovedOptionModule [
      "programs"
      "cyshell"
      "default"
      "session"
    ] "Default session has been removed and been replaced with programs.cyshell.session")
    (lib.mkRenamedOptionModule
      [ "programs" "cyshell" "enableSystemd" ]
      [ "programs" "cyshell" "systemd" "enable" ]
    )
  ];

  options.programs.cyshell = {
    settings = lib.mkOption {
      type = jsonFormat.type;
      default = { };
      description = "CyShell configuration settings as an attribute set, to be written to ~/.config/CyShell/settings.json.";
    };

    clipboardSettings = lib.mkOption {
      type = jsonFormat.type;
      default = { };
      description = "CyShell clipboard settings as an attribute set, to be written to ~/.config/CyShell/clsettings.json.";
    };

    session = lib.mkOption {
      type = jsonFormat.type;
      default = { };
      description = "CyShell session settings as an attribute set, to be written to ~/.local/state/CyShell/session.json.";
    };

    managePluginSettings = lib.mkOption {
      type = lib.types.bool;
      default = hasPluginSettings;
      description = ''Whether to manage plugin settings. Automatically enabled if any plugins have settings configured.'';
    };

    systemd.target = lib.mkOption {
      type = lib.types.str;
      default = config.wayland.systemd.target;
      defaultText = lib.literalExpression "config.wayland.systemd.target";
      description = "Systemd target to bind to.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.quickshell = {
      enable = true;
      inherit (cfg.quickshell) package;
    };

    systemd.user.services.cyshell = lib.mkIf cfg.systemd.enable {
      Unit = {
        Description = "CyShell";
        PartOf = [ cfg.systemd.target ];
        After = [ cfg.systemd.target ];
        Wants = [ "cyshell-runtime-ui.service" "cyshell-shell-ui.service" "cyshell-settings-surface.service" "cyshell-panel.service" "cyshell-desktop.service" "cyshell-osd.service" "cyshell-ui-surfaces.service" ];
      };

      Service = {
        ExecStart = lib.getExe cfg.package + " core";
        Restart = "on-failure";
        RestartForceExitStatus = "TEMPFAIL";
        SuccessExitStatus = "TEMPFAIL";
      };

      Install.WantedBy = [ cfg.systemd.target ];
    };

    xdg.stateFile."CyShell/session.json" = lib.mkIf (cfg.session != { }) {
      source = jsonFormat.generate "session.json" cfg.session;
    };

    xdg.configFile = {
      "CyShell/settings.json" = lib.mkIf (cfg.settings != { }) {
        source = jsonFormat.generate "settings.json" cfg.settings;
      };
      "CyShell/clsettings.json" = lib.mkIf (cfg.clipboardSettings != { }) {
        source = jsonFormat.generate "clsettings.json" cfg.clipboardSettings;
      };
      "CyShell/plugin_settings.json" = lib.mkIf cfg.managePluginSettings {
        source = jsonFormat.generate "plugin_settings.json" pluginSettings;
      };
    }
    // (lib.mapAttrs' (name: value: {
      name = "CyShell/plugins/${name}";
      inherit value;
    }) common.plugins);
    warnings =
      lib.optional (!cfg.managePluginSettings && hasPluginSettings)
        "You have disabled managePluginSettings but provided plugin settings. These settings will be ignored.";
    home.packages = common.packages;
  };
}
