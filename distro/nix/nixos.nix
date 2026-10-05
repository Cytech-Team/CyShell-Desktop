{
  config,
  pkgs,
  lib,
  ...
}@args:
let
  cfg = config.programs.cyshell;
  common = import ./common.nix {
    inherit
      config
      pkgs
      lib
      ;
  };
in
{
  imports = [
    (import ./options.nix args)
  ];
  options.programs.cyshell.systemd.target = lib.mkOption {
    type = lib.types.str;
    description = "Systemd target to bind to.";
    default = "graphical-session.target";
  };
  options.programs.cyshell.lockscreen.securityKey = {
    enable = lib.mkEnableOption "FIDO2/U2F security key unlock for the CyShell lock screen via a dedicated cyshell-u2f PAM service";
    package = lib.mkPackageOption pkgs "pam_u2f" { };
    moduleArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "cue" ];
      description = "Arguments passed to pam_u2f.so in the cyshell-u2f PAM service.";
    };
  };
  config = lib.mkIf cfg.enable {
    systemd.user.services.cyshell = lib.mkIf cfg.systemd.enable {
      description = "CyShell";
      path = lib.mkForce [ ];

      partOf = [ cfg.systemd.target ];
      after = [ cfg.systemd.target ];
      wants = [ "cyshell-runtime-ui.service" "cyshell-shell-ui.service" "cyshell-settings-surface.service" "cyshell-panel.service" "cyshell-desktop.service" "cyshell-osd.service" "cyshell-ui-surfaces.service" ];
      wantedBy = [ cfg.systemd.target ];
      restartIfChanged = cfg.systemd.restartIfChanged;

      serviceConfig = {
        ExecStart = lib.getExe cfg.package + " core";
        Restart = "on-failure";
        RestartForceExitStatus = "TEMPFAIL";
        SuccessExitStatus = "TEMPFAIL";
      };
    };

    environment.systemPackages = [ cfg.quickshell.package ] ++ common.packages;

    environment.etc = lib.mapAttrs' (name: value: {
      name = "xdg/quickshell/cyshell-plugins/${name}";
      inherit value;
    }) common.plugins;

    # CyShell's bundled U2F fallback stack references pam_u2f.so by name, which NixOS's
    # libpam cannot resolve; the dedicated service below uses the absolute store path
    # and is picked up automatically by the lock screen when present.
    security.pam.services."cyshell-u2f" = lib.mkIf cfg.lockscreen.securityKey.enable {
      text = ''
        auth     required ${cfg.lockscreen.securityKey.package}/lib/security/pam_u2f.so ${lib.concatStringsSep " " cfg.lockscreen.securityKey.moduleArgs}
        account  required pam_permit.so
        password required pam_deny.so
        session  required pam_permit.so
      '';
    };

    services.power-profiles-daemon.enable = lib.mkDefault true;
    services.accounts-daemon.enable = lib.mkDefault true;
    services.geoclue2.enable = lib.mkDefault true;
    security.polkit.enable = lib.mkDefault true;
  };
}
