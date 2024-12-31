#!/bin/bash

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "You need to be root to run this script. Exiting."
    exit 1
fi

# Set the variable isRunningArchLinux to true if running Arch Linux
isRunningArchLinux=false

# Check if the system is running Arch Linux
if [[ -f /etc/os-release ]]; then
    if grep -qi "arch" /etc/os-release; then
        isRunningArchLinux=true
    fi
elif [[ -f /etc/arch-release ]]; then
    isRunningArchLinux=true
fi

if [ "$isRunningArchLinux" = false ]; then
    echo "This system is not running Arch Linux. Exiting."
    exit 1
fi

# Check network connectivity by pinging google.com
echo "Checking network connectivity..."
ping -c 4 google.com > /dev/null
if [ $? -ne 0 ]; then
    echo "Please connect to the internet."
    exit 1
fi

# Run lsblk command and display output
echo "Displaying block devices..."
lsblk

# Prompt user if they have formatted their disks
read -p "Have you formatted your disks? (y/n): " formatted
if [[ "$formatted" != "y" ]]; then
    echo "Use the cfdisk command to partition your disks and then rerun the script."
    exit 1
fi

# Prompt user for partitions
while true; do
    read -p "Enter your boot partition (e.g., /dev/sda1): " bootpart
    read -p "Enter your swap partition (e.g., /dev/sda2): " swappart
    read -p "Enter your main partition (e.g., /dev/sda3): " mainpart

    # Check if partitions are valid
    if [[ "$bootpart" == /dev/* && "$swappart" == /dev/* && "$mainpart" == /dev/* ]]; then
        break
    else
        echo "Please ensure all partitions are prefixed with '/dev/'."
    fi
done

# Format the partitions
echo "Formatting partitions..."
mkfs.fat -F32 $bootpart
mkswap $swappart
mkfs.ext4 $mainpart

# Mount the partitions
echo "Mounting partitions..."
mount $mainpart /mnt
mount --mkdir $bootpart /mnt/boot
swapon $swappart

# Install base packages
echo "Installing base system..."
pacstrap -i /mnt base base-devel linux linux-firmware git sudo fastfetch htop intel-ucode nano vim neovim bluez bluez-utils networkmanager

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Display fstab contents and prompt user to verify
echo "Generated fstab. Please verify the contents:"
cat /mnt/etc/fstab
echo "Is the fstab file okay? (y/n)"
read -t 20 -p "Press Enter to skip if no response..." response
if [[ "$response" != "y" && "$response" != "Y" ]]; then
    echo "Exiting. Please verify and rerun the script."
    exit 1
fi

# Arch-chroot into /mnt and set up the root password
echo "Chrooting into /mnt..."
arch-chroot /mnt /bin/bash << EOF
passwd
EOF

# Prompt user for username (min length 4 characters)
while true; do
    read -p "Enter your username (min 4 characters): " username
    if [ ${#username} -ge 4 ]; then
        break
    else
        echo "Username must be at least 4 characters long."
    fi
done

# Create user and set password
arch-chroot /mnt /bin/bash << EOF
useradd -m -g users -G wheel,storage,power,video,audio -s /bin/bash $username
passwd $username
EOF

# Modify sudoers file to allow wheel group members to execute sudo
echo "Editing sudoers file..."
arch-chroot /mnt /bin/bash << EOF
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
EOF

# Set the time zone
while true; do
    read -p "Enter your region/location (e.g., Asia/Kolkata): " region
    if [ -e "/usr/share/zoneinfo/$region" ]; then
        ln -sf /usr/share/zoneinfo/$region /etc/localtime
        hwclock --systohc
        break
    else
        echo "Invalid region/location. Please try again."
    fi
done

# Generate locales
echo "Uncommenting en_AU.UTF-8 UTF-8 in /etc/locale.gen..."
sed -i '/en_AU.UTF-8 UTF-8/s/^#//g' /mnt/etc/locale.gen
arch-chroot /mnt /bin/bash << EOF
locale-gen
EOF

# Set locale.conf
echo "Setting locale..."
echo "LANG=en_AU.UTF-8" > /mnt/etc/locale.conf

# Set the PC hostname
read -p "Enter your PC name: " pcname
echo $pcname > /mnt/etc/hostname
echo -e "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t$pcname.localdomain\t$pcname" > /mnt/etc/hosts

# Install GRUB and related tools
echo "Installing GRUB..."
arch-chroot /mnt pacman -S --noconfirm grub efibootmgr dosfstools mtools

# Install GRUB bootloader
echo "Creating GRUB configuration..."
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# Enable Bluetooth and NetworkManager
echo "Enabling Bluetooth and NetworkManager..."
arch-chroot /mnt systemctl enable bluetooth
arch-chroot /mnt systemctl enable NetworkManager

# Final success message
echo "Arch Linux installation is complete. Please shutdown your computer and reboot."
