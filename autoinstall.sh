#!/usr/bin/env bash

set -e

# Make sure user running the script is root
if [[ ! "$EUID" -eq 0 ]]; then
	echo "This must be run as root!"
	echo "Run 'sudo -i' to switch to the root user."
	exit 1
fi

# Program the yubikey
# ykpersonalize -2 -ochal-resp -ochal-hmac

# The name of the virtual disk to install on
disk="/dev/vda"

# The names of the partitions
boot="/dev/vda1"
root="/dev/vda2"

# The mount point used for the installation
mountpoint="/mnt/nixos"

# Create the partitions
sgdisk -g "$disk"
sgdisk -n 1::+256M --typecode=1:ef00 "$disk"
sgdisk -n 2::-0 --typecode=2:8300 "$disk"
partprobe "$disk"

# Calculate LUKS passphrase
SALT_LENGTH=16
SALT="$(dd if=/dev/random bs=1 count=$SALT_LENGTH 2>/dev/null | rbtohex)"

# Read 2FA password
echo "Enter 2FA password:"
read -s USER_PASSPHRASE

# Calculate the initial challenge and response
CHALLENGE="$(echo -n $SALT | openssl dgst -binary -sha512 | rbtohex)"
RESPONSE=$(ykchalresp -2 -x $CHALLENGE 2>/dev/null)

# Calculate the LUKS slot key
KEY_LENGTH=512
ITERATIONS=1000000
LUKS_KEY="$(echo -n $USER_PASSPHRASE | pbkdf2-sha512 $(($KEY_LENGTH / 8)) $ITERATIONS $RESPONSE | rbtohex)"

# Create the LUKS device
CIPHER=aes-xts-plain64
HASH=sha512
echo -n "$LUKS_KEY" | hextorb | cryptsetup luksFormat --label "NIXOS" --cipher="$CIPHER" --key-size="$KEY_LENGTH" --hash="$HASH" --key-file=- "$root"

# Create the boot filesystem
mkfs.fat -F 32 -n "EFI-NIXOS" "$boot"

# Store the salt and iterations on the boot volume
mount --mkdir "$boot" /boot
mkdir -p /boot/crypt-storage
echo -ne "$SALT\n$ITERATIONS" > /boot/crypt-storage/default
umount /boot

# Open the LUKS device
echo -n "$LUKS_KEY" | hextorb | cryptsetup open "$root" nixos-crypt --key-file=-

# TODO this is less than ideal
#
# Reassign root to /dev/mapper/nixos-crypt
root="/dev/mapper/nixos-crypt"

# Create root filesytem 
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

# TODO there is probably a better way to handle this
#
# Replace the initial configuration with the minimal configuration
# url="https://raw.githubusercontent.com/Kodlak15/nix-minimal-autoinstall/master/configuration.nix"
# config="$(curl "$url")"
config="$(cat ./configuration.nix)"
echo "$config" > "$mountpoint/etc/nixos/configuration.nix"

# Install the system
nixos-install --root "$mountpoint"

# Unmount all volumes
umount -R "$mountpoint"

# Close the LUKS partition
cryptsetup luksClose "nixos-crypt"

echo "NixOS was installed successfully!"
echo "You may now reboot and begin building your system."
echo "If you are going to build using a flake, be sure to add the generated hardware-configuration.nix to the repository."
