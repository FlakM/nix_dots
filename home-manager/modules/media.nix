{ pkgs, ... }:
{
  programs.mpv = {
    enable = true;
    config = {
      hwdec = "vaapi";
      vo = "gpu-next";
      gpu-api = "vulkan";
      gpu-context = "waylandvk";
      profile = "gpu-hq";
      scale = "ewa_lanczossharp";
      cscale = "ewa_lanczossharp";
      video-sync = "display-resample";
      interpolation = true;
      tscale = "oversample";
    };
  };

  home.packages = with pkgs; [
    ffmpeg-full
    imv
    swappy
  ];

  xdg.configFile."swappy/config".text = ''
    [Default]
    save_dir=$HOME/Pictures
    save_filename_format=swappy-%Y%m%d-%H%M%S.png
    show_panel=true
    line_size=5
    text_size=20
    text_font=sans-serif
    paint_mode=brush
    early_exit=false
    fill_shape=false
  '';

  xdg.configFile."xfce4/xfconf/xfce-perchannel-xml/thunar.xml".force = true;
  xdg.configFile."xfce4/xfconf/xfce-perchannel-xml/thunar.xml".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <channel name="thunar" version="1.0">
      <property name="default-view" type="string" value="ThunarDetailsView"/>
      <property name="last-view" type="string" value="ThunarDetailsView"/>
      <property name="last-sort-column" type="string" value="THUNAR_COLUMN_DATE_MODIFIED"/>
      <property name="last-sort-order" type="string" value="GTK_SORT_DESCENDING"/>
    </channel>
  '';

  xdg.mimeApps.defaultApplications = {
    "inode/directory" = "thunar.desktop";
    "image/png" = "imv-dir.desktop";
    "image/jpeg" = "imv-dir.desktop";
    "image/gif" = "imv-dir.desktop";
    "image/bmp" = "imv-dir.desktop";
    "image/webp" = "imv-dir.desktop";
    "image/tiff" = "imv-dir.desktop";
    "image/svg+xml" = "imv-dir.desktop";
    "video/mp4" = "mpv.desktop";
    "video/mkv" = "mpv.desktop";
    "video/webm" = "mpv.desktop";
    "video/x-matroska" = "mpv.desktop";
    "audio/mpeg" = "mpv.desktop";
    "audio/flac" = "mpv.desktop";
    "audio/ogg" = "mpv.desktop";
    "application/pdf" = "firefox.desktop";
    "text/plain" = "nvim.desktop";
  };
}
