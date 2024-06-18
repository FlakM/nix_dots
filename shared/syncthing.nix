{ pkgs, config, ... }:
{
  services = {
    syncthing = {
      enable = true;
      user = "flakm";
      dataDir = "/home/flakm/";
      configDir = "/home/flakm/Documents/.config/syncthing";
      overrideDevices = true; # overrides any devices added or deleted through the WebUI
      overrideFolders = true; # overrides any folders added or deleted through the WebUI
      settings = {
        devices = {
          "pixel" = { id = "CS543I2-6DUUOEB-EMPHN7L-KEMEWMD-CG5KS57-W24GPRA-JZA46Y6-UEPYXQ4"; };
          "mac-air" = { id = "DEVICE-ID-GOES-HERE"; };
        };
        folders = {
          "obsidian" = {
            # Name of folder in Syncthing, also the folder ID
            path = "/home/flakm/programming/flakm/obsidian/"; # Which folder to add to Syncthing
            devices = [ "pixel" ]; # Which devices to share the folder with
            ignorePerms = false; # By default, Syncthing doesn't sync file permissions. This line enables it for this folder.
          };
        };
      };
    };
  };

}
