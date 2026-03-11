{ pkgs, secrets, ... }:
{
  fileSystems = builtins.listToAttrs (map (mount: {
    name = mount.mountPath;
    value = {
      device = "/dev/disk/by-uuid/${mount.storageUUID}";
      fsType = "ext4";
      options = [
        "defaults"
        "nofail"
        "user"
        "exec"
        "rw"
      ];
    };
  }) secrets.storageMount);
}
