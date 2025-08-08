#!/bin/bash
# ============================================================
# Interactive Lazy Gentoo Installer
# Author: Your Name
# License: MIT
# GitHub: https://github.com/yourusername/lazy-gentoo-installer
#
# Description:
#   This script installs Gentoo Linux quickly using official
#   binary packages, a precompiled kernel, and optional desktop
#   environments (XFCE or KDE Plasma).
#
#   Designed to run from SystemRescue or Gentoo minimal ISO.
#
# WARNING:
#   This will ERASE the target disk completely.
# ============================================================

set -e

# --- Helper: Prompt with default ---
prompt() {
    local PROMPT_TEXT="$1"
    local DEFAULT="$2"
    read -rp "$PROMPT_TEXT [$DEFAULT]: " INPUT
    echo "${INPUT:-$DEFAULT}"
}

echo "=== Interactive Lazy Gentoo Installer ==="
echo "WARNING: This will ERASE the target disk completely!"
echo

# --- Disk selection ---
lsblk -dpno NAME,SIZE | grep -E "/dev/sd|/dev/nvme"
DISK=$(prompt "Enter target disk (e.g., /dev/sda or /dev/nvme0n1)" "")
if [[ -z "$DISK" ]]; then
    echo "No disk selected. Aborting."
    exit 1
fi

read -rp "Are you sure you want to erase $DISK? (yes/NO): " CONFIRM
[[ "$CONFIRM" != "yes" ]] && { echo "Aborted."; exit 1; }

# --- System settings ---
HOSTNAME=$(prompt "Enter hostname" "gentoo")
TIMEZONE=$(prompt "Enter timezone" "Europe/Berlin")
LOCALE=$(prompt "Enter locale" "en_US.UTF-8 UTF-8")

echo "Choose desktop environment:"
echo "1) XFCE"
echo "2) KDE Plasma"
echo "3) CLI only"
DESKTOP_CHOICE=$(prompt "Enter choice" "1")

ROOTPASS=$(prompt "Enter root password" "gentoo")

# --- Gentoo sources ---
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc-latest.tar.xz"
BINHOST="https://distfiles.gentoo.org/releases/amd64/binpackages/17.1/x86-64/"

# --- Summary ---
echo
echo "=== Summary ==="
echo "Disk: $DISK"
echo "Hostname: $HOSTNAME"
echo "Timezone: $TIMEZONE"
echo "Locale: $LOCALE"
echo "Desktop: $DESKTOP_CHOICE"
echo "Root password: $ROOTPASS"
echo
read -rp "Proceed with installation? (yes/NO): " FINALCONFIRM
[[ "$FINALCONFIRM" != "yes" ]] && { echo "Aborted."; exit 1; }

# --- Partition disk ---
echo ">>> Partitioning $DISK..."
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+512M -t 1:EF00 -c 1:"EFI System" "$DISK"
sgdisk -n 2:0:0     -t 2:8300 -c 2:"Gentoo Root" "$DISK"

# --- Format partitions ---
echo ">>> Formatting partitions..."
mkfs.vfat -F 32 "${DISK}1"
mkfs.ext4 -F "${DISK}2"

# --- Mount filesystems ---
mount "${DISK}2" /mnt/gentoo
mkdir /mnt/gentoo/boot
mount "${DISK}1" /mnt/gentoo/boot

# --- Download and extract Stage 3 ---
echo ">>> Downloading Stage 3..."
cd /mnt/gentoo
wget "$STAGE3_URL" -O stage3.tar.xz
tar xpvf stage3.tar.xz --xattrs-include='*.*' --numeric-owner

# --- Configure Portage for binary packages ---
echo "FEATURES=\"getbinpkg\"" >> /mnt/gentoo/etc/portage/make.conf
echo "PORTAGE_BINHOST=\"$BINHOST\"" >> /mnt/gentoo/etc/portage/make.conf

# --- Mount system directories ---
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev

# --- Chroot and install system ---
cat <<EOF | chroot /mnt/gentoo /bin/bash
source /etc/profile
export PS1="(chroot) \$PS1"

# Timezone & Locale
echo "$TIMEZONE" > /etc/timezone
emerge --config sys-libs/timezone-data
echo "$LOCALE" > /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
env-update && source /etc/profile

# Hostname
echo "$HOSTNAME" > /etc/hostname

# Install kernel (binary)
emerge --getbinpkg gentoo-kernel-bin

# Networking
emerge --getbinpkg dhcpcd networkmanager
rc-update add NetworkManager default

# Bootloader
emerge --getbinpkg grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Gentoo
grub-mkconfig -o /boot/grub/grub.cfg

# Root password
echo "root:$ROOTPASS" | chpasswd

# Desktop environment
if [[ "$DESKTOP_CHOICE" == "1" ]]; then
    emerge --getbinpkg xfce4 lightdm lightdm-gtk-greeter
    rc-update add lightdm default
elif [[ "$DESKTOP_CHOICE" == "2" ]]; then
    emerge --getbinpkg plasma-meta sddm
    rc-update add sddm default
fi
EOF

# --- Finish ---
umount -R /mnt/gentoo
echo "=== Installation complete! Root password is '$ROOTPASS'. Reboot now. ==="
