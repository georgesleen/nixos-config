# ScopeTek DCM310 / AmScope MD800E microscope camera (0547:4d33). See NOTES.md.

{ config, pkgs, ... }:

let
  python = pkgs.python3.withPackages (ps: [ ps.pyusb ]);

  # Sensor skip modes the streamer offers. 2048x1536 streams but loses packets
  # with synchronous reads, so the default is the largest size that arrives
  # whole every frame.
  microscope = pkgs.writeShellApplication {
    name = "microscope";
    runtimeInputs = [
      pkgs.ffmpeg
      pkgs.v4l-utils
    ];
    text = ''
      mode="''${1:-1024x768}"
      node=/dev/video9
      if [ ! -e "$node" ]; then
        echo "microscope: $node missing, is the v4l2loopback module loaded?" >&2
        exit 1
      fi
      echo "microscope: streaming $mode to $node (Ctrl-C to stop)" >&2
      ${python}/bin/python3 ${./usb-microscope.py} --mode "$mode" \
        | ffmpeg -loglevel warning \
            -f rawvideo -pix_fmt bayer_grbg8 -s "$mode" \
            -use_wallclock_as_timestamps 1 -i - \
            -pix_fmt yuyv422 -f v4l2 "$node"
    '';
  };
in

{
  # exclusive_caps makes the node advertise capture only, which is what apps
  # that reject output-capable devices (Firefox, Chromium) require.
  boot.extraModprobeConfig = ''
    options v4l2loopback video_nr=9 card_label="USB Microscope" exclusive_caps=1 max_buffers=8
  '';
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  boot.kernelModules = [ "v4l2loopback" ];
  environment.systemPackages = [ microscope ];
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0547", ATTRS{idProduct}=="4d33", MODE="0660", GROUP="plugdev"
  '';
}
