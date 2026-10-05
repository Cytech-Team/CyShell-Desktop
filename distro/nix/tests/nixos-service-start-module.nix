{
  self,
  pkgs,
  ...
}:
let
  fakeCyShell = pkgs.writeShellScriptBin "cyshell" ''
    printf '%s\n' "$@" > /tmp/cyshell-service-args
    exec ${pkgs.coreutils}/bin/sleep 300
  '';
in
pkgs.testers.runNixOSTest {
  name = "cyshell-nixos-service-start-module";

  nodes.machine = {
    imports = [
      self.nixosModules.cyshell
    ];

    users.users.danklinux = {
      isNormalUser = true;
      linger = true;
      extraGroups = [ "wheel" ];
    };

    programs.cyshell = {
      enable = true;
      package = fakeCyShell;
      systemd = {
        enable = true;
        target = "default.target";
      };
    };

    system.stateVersion = "25.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1000.service")

    machine.succeed("systemctl --machine=danklinux@ --user start cyshell.service")
    machine.wait_until_succeeds("systemctl --machine=danklinux@ --user is-active cyshell.service")
    machine.wait_until_succeeds("test -f /tmp/cyshell-service-args")
    machine.succeed("grep -Fx core /tmp/cyshell-service-args")
  '';
}
