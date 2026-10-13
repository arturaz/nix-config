# The USB speakers (a TI PCM2902 USB audio chip, sold as "C-Media USB PnP Sound
# Device"): volume is done in software, with the chip's own volume left at maximum.
{ pkgs, ... }:

let
  vendorId = "08bb";
  productId = "2902";
in
{
  # The chip's hardware volume only spans -28 dB to 0 dB. PipeWire maps its volume onto
  # that range, so everything under ~35% hit the bottom step, which is silent. With the
  # soft mixer, PipeWire doesn't touch the hardware volume and attenuates in software
  # over the full range.
  services.pipewire.wireplumber.extraConfig."50-usb-speakers-soft-mixer" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          {
            "device.vendor.id" = "0x${vendorId}";
            "device.product.id" = "0x${productId}";
          }
        ];
        actions.update-props."api.alsa.soft-mixer" = true;
      }
    ];
  };

  # PipeWire no longer sets the hardware volume, so put it at maximum whenever the
  # speakers are plugged in (incl. at boot).
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="sound", KERNEL=="controlC*", ATTRS{idVendor}=="${vendorId}", ATTRS{idProduct}=="${productId}", RUN+="${pkgs.alsa-utils}/bin/amixer -q -c %n sset PCM 100%% unmute"
  '';
}
