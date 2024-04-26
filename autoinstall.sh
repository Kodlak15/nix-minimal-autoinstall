#!/usr/bin/env nix-shell
# nix-shell -i bash --pure
# nix-shell -p home-manager

set -e

# Make sure user running the script is root
if [[ ! "$EUID" -eq 0 ]]; then
	echo "This must be run as root!"
	echo "Run 'sudo -i' to switch to the root user."
	exit 1
fi

# The name of the virtual disk to install on
disk="/dev/vda"

# The names of the partitions
boot="/dev/vda1"
root="/dev/vda2"

# The mount point used for the installation
mountpoint="/mnt/nixos"

# Get the NixOS version
version="$(nixos-version | cut -d '.' -f 1,2)"

# Get a username from the user
echo "Enter a username you would like added to the installation"
echo "If building from a flake later, it would be best if the username exists in the flake as well"
read -p "Username: " username

# Set a directory path for the flake (relative to new root, not installation image root)
flakedir="/home/$username/nix-config"

# A minimal configuration to install the base system
configuration='
{pkgs, ...}: {
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

	users.users.$username = {
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

  services.openssh.enable = true;

  # Do not change this value!
  system.stateVersion = "$version";
}
'

# Create the partitions
sgdisk -g "$disk"
sgdisk -n 1::+256M --typecode=1:ef00 "$disk"
sgdisk -n 2::-0 --typecode=2:8300 "$disk"
partprobe "$disk"

# Create filesystems
mkfs.fat -F 32 -n "EFIBOOT" "$boot"
mkfs.btrfs -L "NIXOS" "$root" -f

# Create subvolumes
mount --mkdir "$root" "$mountpoint"
btrfs subvolume create "$mountpoint/@"
btrfs subvolume create "$mountpoint/@home"
btrfs subvolume create "$mountpoint/@tmp"
btrfs subvolume create "$mountpoint/@var"
umount "$mountpoint"

# Mount the subvolumes
mount -o subvol="@" "$root" "$mountpoint"
mount --mkdir -o subvol="@home" "$root" "$mountpoint/home"
mount --mkdir -o subvol="@tmp" "$root" "$mountpoint/tmp"
mount --mkdir -o subvol="@var" "$root" "$mountpoint/var"

# Mount the boot partition
mount --mkdir "$boot" "$mountpoint/boot"

# Generate the initial configuration
nixos-generate-config --root "$mountpoint"

# Replace the initial configuration with the minimal configuration
echo "$configuration" > "$mountpoint/etc/nixos/configuration.nix"

# Install the system
nixos-install --root "$mountpoint"

# Unmount all volumes
umount -R "$mountpoint"

# Build system from flake if desired
read -p "Would you like to build the system with a flake? (y/n): " useflake
if [[ $(echo "$useflake" | xargs) == "y" ]]; then
	read -p "Enter the url for the repository containing the flake you would like to use: " url
	nix flake clone $url --dest "$flakedir"
	read -p "Enter the name of the flake you would like to use: " flake
	chroot "$mountpoint"
	nixos-rebuild-switch --flake "$flakedir#$flake"
	home-manager switch --flake "$flakedir#$flake"
	exit
fi

echo "NixOS was installed successfully!"
