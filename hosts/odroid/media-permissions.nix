{ config, pkgs, lib, ... }:

{
  users.groups.media = {
    members = [
      "deluge"
      "sabnzbd"
      "sonarr"
      "readarr"
      "radarr"
      "jellyfin"
      "jellyseerr"
      "audiobookshelf"
      "flakm"
    ];
  };

  users.users.deluge.extraGroups = [ "media" ];
  users.users.sabnzbd.extraGroups = [ "media" ];
  users.users.sonarr.extraGroups = [ "media" "sabnzbd" ];
  users.users.readarr.extraGroups = [ "media" ];
  users.users.radarr.extraGroups = [ "media" "sabnzbd" ];
  users.users.jellyfin.extraGroups = [ "media" "render" "video" "sabnzbd" ];
  users.users.audiobookshelf.extraGroups = [ "media" ];

  systemd.services.deluged.serviceConfig = {
    UMask = lib.mkForce "0002";
  };

  systemd.services.sabnzbd.serviceConfig = {
    UMask = lib.mkForce "0002";
  };

  systemd.services.sonarr.serviceConfig = {
    UMask = lib.mkForce "0002";
  };

  systemd.services.readarr.serviceConfig = {
    UMask = lib.mkForce "0002";
  };

  systemd.services.radarr.serviceConfig = {
    UMask = lib.mkForce "0002";
  };

  systemd.services.jellyfin.serviceConfig = {
    UMask = lib.mkForce "0002";
  };

  systemd.services.audiobookshelf.serviceConfig = {
    UMask = lib.mkForce "0002";
  };

  systemd.tmpfiles.rules = [
    "d /var/media 0775 deluge media - -"
    "d /var/media/grownups 2775 deluge media - -"
    "d /var/media/grownups/seriale 2775 deluge media - -"
    "d /var/media/grownups/filmy 2775 deluge media - -"
    "d /var/media/kids 2775 deluge media - -"
    "d /var/media/audiobookshelf 2775 audiobookshelf media - -"
    "d /var/media/podcasty 2775 audiobookshelf media - -"
  ];

  system.activationScripts.fixMediaPermissions = {
    text = ''
      echo "Fixing media directory permissions..."

      find /var/media -type f -exec chgrp media {} \; 2>/dev/null || true
      find /var/media -type d -exec chgrp media {} \; 2>/dev/null || true
      find /var/media -type f -exec chmod g+rw {} \; 2>/dev/null || true
      find /var/media -type d -exec chmod 2775 {} \; 2>/dev/null || true

      chgrp -R media /var/lib/sabnzbd/Downloads 2>/dev/null || true
      chmod -R g+rwX /var/lib/sabnzbd/Downloads 2>/dev/null || true
      find /var/lib/sabnzbd/Downloads -type d -exec chmod 2775 {} \; 2>/dev/null || true

      echo "Media permissions fixed"
    '';
    deps = [];
  };
}
