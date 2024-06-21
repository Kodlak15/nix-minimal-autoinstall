{
  pkgs,
  lib,
  ...
}: let
  username = "user";
  version = "24.05";
in {
  imports = [
    ./hardware-configuration.nix
  ];

  nix.settings.experimental-features = ["nix-command" "flakes"];

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    initrd = {
      # Required to open the EFI partition and Yubikey
      kernelModules = ["vfat" "nls_cp437" "nls_iso8859-1" "usbhid"];

      luks = {
        # Support for Yubikey PBA
        yubikeySupport = true;

        devices."nixos-crypt" = {
          device = lib.mkDefault "/dev/disk/by-label/NIXOS"; # Be sure to update this to the correct volume

          yubikey = {
            slot = 2;
            twoFactor = true; # Set to false for 1FA
            gracePeriod = 30; # Time in seconds to wait for Yubikey to be inserted
            keyLength = 64; # Set to $KEY_LENGTH/8
            saltLength = 16; # Set to $SALT_LENGTH

            storage = {
              device = lib.mkDefault "/dev/disk/by-label/EFI-NIXOS"; # Be sure to update this to the correct volume
              fsType = "vfat";
              path = "/crypt-storage/default";
            };
          };
        };
      };
    };
  };

  networking.hostName = "default";
  networking.networkmanager.enable = true;

  sound.enable = true;
  hardware.pulseaudio.enable = true;

  users.users.${username} = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    packages = with pkgs; [
      gnumake
      git
      tree
    ];
  };

  environment.systemPackages = with pkgs; [
    neovim
    wget
    neofetch
  ];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Yubikey support
  hardware.gpgSmartcards.enable = true;

  services.openssh.enable = true;

  # Do not change this value!
  system.stateVersion = "${version}";
}
