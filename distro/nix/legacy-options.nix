{ lib, ... }:
{
  imports = [
    (lib.mkRenamedOptionModule [ "programs" "dankMaterialShell" ] [ "programs" "cyshell" ])
    (lib.mkRenamedOptionModule [ "programs" "dank-material-shell" ] [ "programs" "cyshell" ])
  ];
}
