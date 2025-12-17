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
  ];
}
