# common.nix — configuration shared by every navigation host.
#
# Brings up the navigation stack (services.navigation) plus the baseline a
# headless boat computer needs: an admin account, SSH, mDNS (.local resolution
# and zeroconf service discovery) and flakes. Host files add the hostname, the
# HAT and the boot/bootloader specifics.

{ lib, pkgs, ... }:

{
  imports = [ ../modules/navigation.nix ];

  # Baseline tooling useful on every boat box, headless or not.
  environment.systemPackages = [
    pkgs.git
    pkgs.zip
  ];

  # Make the flake's custom marine packages (pypilot, signalk-server, …) resolve
  # for the service modules' `package` defaults. Applied here rather than in the
  # module so navigation.nix stays usable where pkgs is pinned (NixOS tests).
  nixpkgs.overlays = [ (final: _prev: import ../pkgs final) ];

  # Whole stack from a single switch; the headless services default on and stay
  # overridable per host (opencpn is GUI, so left off here).
  services.navigation = {
    enable = true;
    signalk.enable = lib.mkDefault true;
    pypilot.enable = lib.mkDefault true;
    gps.enable = lib.mkDefault true;
  };

  # Admin account. initialPassword is a first-boot convenience: change it or
  # replace it with SSH keys before going to sea.
  users.users.skipper = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "NixPypilot";

    # Deploy key (gponcon@gmail.com): enables key-based `nixos-rebuild
    # --target-host skipper@…` without ssh-copy-id.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEKerVgYq/5RlpOPvDVBTHNoY3AM7NLJ9BBvWvW9Us2h gponcon@gmail.com"
    ];
  };

  # Passwordless sudo for wheel so `nixos-rebuild --use-remote-sudo` activates
  # without an interactive prompt.
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = lib.mkDefault true;
  };

  # French (azerty) keyboard, console and graphical session alike.
  console.keyMap = "fr";
  services.xserver.xkb.layout = "fr";

  # Resolve <host>.local (deploy workflow) and let pypilot/signalk discover each
  # other over zeroconf.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      userServices = true;
    };
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # GPS disciplines the clock at sea; default the box itself to UTC.
  time.timeZone = lib.mkDefault "UTC";

  system.stateVersion = lib.mkDefault "26.11";
}
