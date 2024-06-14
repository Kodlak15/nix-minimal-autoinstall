{pkgs, ...}: let
  username = "user";
  version = "24.05";
in {
  imports = [
    ./hardware-configuration.nix
  ];

  nix.settings.experimental-features = ["nix-command" "flakes"];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

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
