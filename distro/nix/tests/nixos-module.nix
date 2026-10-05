{
  self,
  pkgs,
  ...
}:
pkgs.testers.runNixOSTest {
  name = "cyshell-nixos-module";

  nodes.machine = {
    imports = [
      self.nixosModules.cyshell
    ];

    users.users.danklinux = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };

    programs.cyshell = {
      enable = true;
      systemd.enable = true;
      lockscreen.securityKey.enable = true;
      plugins = {
        TestPlugin = {
          src = pkgs.emptyDirectory;
        };
      };
    };

    system.stateVersion = "25.11";
  };

  testScript = ''
    import json

    machine.wait_for_unit("multi-user.target")

    machine.succeed("command -v cyshell")
    machine.succeed("command -v quickshell")
    machine.succeed("su -- danklinux -c 'cyshell --help >/dev/null'")
    machine.succeed("test -d /etc/xdg/quickshell/cyshell-plugins")
    machine.succeed("test -f /run/current-system/sw/lib/systemd/user/cyshell.service")
    machine.succeed("grep -q 'lib/security/pam_u2f.so cue' /etc/pam.d/cyshell-u2f")

    payload = json.loads(machine.succeed("su -- danklinux -c 'cyshell doctor --json'"))
    t.assertIn("summary", payload)
    t.assertIsInstance(payload.get("results"), list)
  '';
}
