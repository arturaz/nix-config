# Hardware video decoding (VA-API) on Intel GPUs from Broadwell on, for VLC and Firefox.
{ pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    extraPackages = [ pkgs.intel-media-driver ];
  };
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
}
