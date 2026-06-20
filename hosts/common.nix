# common.nix — configuration shared by every navigation host.
#
# Brings up the navigation stack (services.navigation) plus the baseline a
# headless boat computer needs: an admin account, SSH, mDNS (.local resolution
# and zeroconf service discovery) and flakes. Host files add the hostname, the
# HAT and the boot/bootloader specifics.

{ lib, pkgs, ... }:

let
  # Admin deploy key (gponcon@gmail.com): key-based SSH + trusted closure push.
  deployKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEKerVgYq/5RlpOPvDVBTHNoY3AM7NLJ9BBvWvW9Us2h gponcon@gmail.com"
  ];
in
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
  nixpkgs.overlays = [ (import ../pkgs) ];

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

    # Key-based `nixos-rebuild --target-host skipper@…` without ssh-copy-id.
    openssh.authorizedKeys.keys = deployKeys;
  };

  # Same key for root: `--target-host root@…` works (root is always a trusted
  # Nix user — the path used to bootstrap trusted-users below).
  users.users.root.openssh.authorizedKeys.keys = deployKeys;

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

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Wheel admins may push unsigned closures over `nixos-rebuild
    # --target-host` (deploys come from a trusted workstation). root is trusted
    # by default; add wheel.
    trusted-users = [ "@wheel" ];
  };

  # GPS disciplines the clock at sea; default the box itself to UTC.
  time.timeZone = lib.mkDefault "UTC";

  system.stateVersion = lib.mkDefault "25.11";
}
