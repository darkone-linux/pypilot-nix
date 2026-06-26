# Camera Module 3 Wide — Raspberry Pi CSI camera add-on (IMX708 sensor).
#
# Interfaces:
#  - CSI-2 : IMX708 wide-angle sensor on the camera connector (no 40-pin GPIO).
#  - libcamera/dt-overlay (imx708) feeding the unicam V4L2 capture pipeline.
#  - Optional network streaming through MediaMTX (RTSP + WebRTC), fed by a
#    GStreamer libcamerasrc → hardware H.264 pipeline.
#
# Sits on the dedicated CSI connector, so it claims no header GPIOs and stays
# compatible with every HAT above (no gpioClaims entry needed).

{
  config,
  options,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.navigation;
  cam = cfg.hardware.modules;
  stream = cam.camera3Wide.streaming;
  inherit (lib)
    mkIf
    mkMerge
    mkEnableOption
    mkOption
    optionalAttrs
    types
    ;

  # The vendor config.txt option exists only on the nixos-raspberrypi base
  # (Pi hosts), not on the plain-nixpkgs lab VM. Emit the overlay only where it
  # is declared, so the module stays evaluable everywhere.
  hasConfigTxt = options.hardware ? raspberry-pi;

  # GStreamer with just the elements the pipeline needs: core, base
  # (videoconvert), good (v4l2 HW H.264 encoder), bad (h264parse), rtsp-server
  # (rtspclientsink) and libcamera (libcamerasrc). Pointed at via the plugin
  # search path so no global GStreamer install is required.
  gstPlugins = [

    # `.out`: gstreamer's plugins (coreelements: capsfilter, queue…) live there,
    # not in its default `-bin` output (which holds only the gst-launch binary).
    pkgs.gst_all_1.gstreamer.out
    pkgs.gst_all_1.gst-plugins-base
    pkgs.gst_all_1.gst-plugins-good
    pkgs.gst_all_1.gst-plugins-bad
    pkgs.gst_all_1.gst-rtsp-server
    pkgs.libcamera
  ];
  gstPluginPath = lib.makeSearchPath "lib/gstreamer-1.0" gstPlugins;

  # CSI sensor → hardware H.264 → local RTSP, which MediaMTX republishes as RTSP
  # (8554) and WebRTC (8889). Run on demand by MediaMTX, so the camera is only
  # powered while a client is connected.
  streamPipeline = pkgs.writeShellScript "camera3-wide-stream" ''
    export GST_PLUGIN_SYSTEM_PATH_1_0=${gstPluginPath}

    exec ${pkgs.gst_all_1.gstreamer.bin}/bin/gst-launch-1.0 -e \
      libcamerasrc ! \
      video/x-raw,width=${toString stream.width},height=${toString stream.height},framerate=${toString stream.framerate}/1 ! \
      videoconvert ! \
      v4l2h264enc ! \
      h264parse config-interval=1 ! \
      rtspclientsink location=rtsp://localhost:8554/cam
  '';
in
{
  options.services.navigation.hardware.modules.camera3Wide.streaming = {
    enable = mkEnableOption "RTSP/WebRTC streaming of the Camera Module 3 via MediaMTX";

    width = mkOption {
      type = types.int;
      default = 1280;
      description = "Capture width in pixels for the network stream.";
    };

    height = mkOption {
      type = types.int;
      default = 720;
      description = "Capture height in pixels for the network stream.";
    };

    framerate = mkOption {
      type = types.int;
      default = 30;
      description = "Capture frame rate (fps) for the network stream.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the RTSP (8554) and WebRTC (8889/8189) ports to the network.";
    };
  };

  config = mkMerge [
    {

      # Streaming has no camera to read without the sensor enabled.
      assertions = [
        {
          assertion = stream.enable -> cam.enableCamera3Wide;
          message = "camera3Wide.streaming.enable requires hardware.modules.enableCamera3Wide.";
        }
      ];
    }

    (mkIf cam.enableCamera3Wide (mkMerge [
      {

        # libcamera userspace + the `cam` test tool for bench capture/preview;
        # the sensor is read through the unicam V4L2 nodes (/dev/video*).
        environment.systemPackages = [ pkgs.libcamera ];
      }

      # Pin the IMX708 on the vendor firmware config.txt: turn off the
      # auto-detect guess and load the imx708 overlay explicitly on the CSI port.
      (optionalAttrs hasConfigTxt {
        hardware.raspberry-pi.config.all = {
          options.camera_auto_detect = {
            enable = true;

            # Integer 0, not boolean false: the renderer does `toString value`,
            # and `toString false` is "" (→ a blank, ignored directive).
            value = 0;
          };
          dt-overlays.imx708 = {
            enable = true;
            params = { };
          };
        };
      })
    ]))

    (mkIf (cam.enableCamera3Wide && stream.enable) {

      # MediaMTX runs the GStreamer pipeline on demand and serves it as RTSP +
      # WebRTC. allowVideoAccess puts its DynamicUser in the video group for the
      # camera and the H.264 encoder device nodes.
      services.mediamtx = {
        enable = true;
        allowVideoAccess = true;
        settings = {
          logLevel = "info";
          paths.cam = {
            runOnDemand = "${streamPipeline}";
            runOnDemandRestart = true;
          };
        };
      };

      # libcamera also maps frame buffers through the DMA-BUF heaps; the vendor
      # udev rules are not shipped here, so grant the video group access.
      services.udev.extraRules = ''
        SUBSYSTEM=="dma_heap", GROUP="video", MODE="0660"
      '';

      networking.firewall = mkIf stream.openFirewall {

        # RTSP control (8554) + WebRTC HTTP signalling (8889); WebRTC media is
        # negotiated over UDP/8189 (the default ICE port).
        allowedTCPPorts = [
          8554
          8889
        ];
        allowedUDPPorts = [ 8189 ];
      };
    })
  ];
}
