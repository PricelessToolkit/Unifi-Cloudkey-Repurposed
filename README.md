# UniFi Cloud Key Gen2+ — Debian Rescue & Install Wiki
Replace UniFi OS on the Cloud Key Gen2 Plus with a standard Debian ARM64 root filesystem, enabling normal disk mounting and Linux workflows. Includes serial rescue, full eMMC backup, staged Debian upgrades, and recovery instructions.

Original post https://xdaforums.com/t/unifi-cloud-key-gen-2-plus.4664639/

> ⚠️ **WARNING**  
> This procedure modifies the internal eMMC of the device.  
> Incorrect use of `dd` or partitioning commands **can permanently brick the device**.  
> Always perform the backup step before proceeding.

---

## Overview

This guide replaces UniFi OS on a **Cloud Key Gen2 Plus** with a minimal **Debian ARM64** system, using:
- a custom boot image
- a custom root filesystem
- a step-by-step Debian upgrade path (Jessie → Bookworm)

---

## 1. Disassemble Device and Access Serial Header

Follow this guide to disassemble the device and gain access to the **J22 serial header**:

```
https://colincogle.name/blog/unifi-cloud-key-rescue/
```

---

## 2. Boot Into Recovery Mode and Log In

Boot the device into recovery mode.

Login via serial console:

```
login: root
password: ubnt
```

---

## 3. Backup the Original MMC (CRITICAL)

Insert a **blank SD card larger than 32GB**.

Backup the internal eMMC to the SD card:

```bash
dd if=/dev/mmcblk0 of=/dev/mmcblk1 conv=noerror,sync
```

This creates a full raw backup of the device storage.

---

## 4. Mount USB Drive With Custom Boot Image

Insert a USB drive containing:

```
custom_boot.img
```

Mount the USB drive:

```bash
mkdir /tmp/flash
mount /dev/sdb1 /tmp/flash
```

---

## 5. Flash the Custom Boot Image

Flash the boot image to the existing boot partition:

```bash
dd if=/tmp/flash/custom_boot.img of=/dev/mmcblk0p42
```

---

## 6. Repartition Internal MMC

Open `parted`:

```bash
parted /dev/mmcblk0
```

Delete existing partitions:

```bash
rm 44
rm 45
rm 46
rm 47
```

Create a new EXT4 partition using the available space, **ensuring the partition number is 44**:

```bash
mkpart primary ext4
```

Exit `parted`:

```bash
quit
```

---

## 7. Format the New Root Partition

Format partition 44:

```bash
mkfs.ext4 /dev/mmcblk0p44
```

---

## 8. Obtain Debian ARM64 Root Filesystem

Use the following root filesystem archive:

```
arm64-rootfs-20170318T102424Z.tar.gz
```

---

## 9. Copy RootFS to External Drive and Mount It

Copy `arm64-rootfs-20170318T102424Z.tar.gz` to an external USB drive.

Mount the external drive:

```bash
mount /dev/sdb1 /mnt
```

---

## 10. Mount Partition 44 and Extract RootFS

Mount the new root partition:

```bash
mount /dev/mmcblk0p44 /mnt/root
```

Extract the root filesystem:

```bash
tar -xpf /mnt/arm64-rootfs-20170318T102424Z.tar.gz -C /mnt/root
```

---

## 11. Reboot Into Debian Jessie

Reboot the device:

```bash
reboot
```

Result:
- Boots into **Debian Jessie**
- SSH enabled
- No password set

---

## 12. Upgrade Debian Step-by-Step to Bookworm

Debian **must be upgraded one release at a time**.

Upgrade path:

```
Jessie → Stretch → Buster → Bullseye → Bookworm
```

---

### Jessie → Stretch

```bash
nano /etc/apt/sources.list
```

```text
deb http://archive.debian.org/debian stretch main contrib non-free
```

```bash
apt update
apt dist-upgrade
reboot
```

---

### Stretch → Buster

```bash
nano /etc/apt/sources.list
```

```text
deb http://deb.debian.org/debian buster main contrib non-free
```

```bash
apt update
apt dist-upgrade
reboot
```

---

### Buster → Bullseye

```bash
nano /etc/apt/sources.list
```

```text
deb http://deb.debian.org/debian bullseye main contrib non-free
```

```bash
apt update
apt dist-upgrade
reboot
```

---

### Bullseye → Bookworm

```bash
nano /etc/apt/sources.list
```

```text
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
```

```bash
apt update
apt dist-upgrade
reboot
```

---

## 13. Restore ck-splash (LED Control)

Copy `ck-splash` from the backup to `/sbin/`:

```bash
cp ck-splash /sbin/
```

---

## Recovery: Restore Device From SD Card Backup (CD)

This section restores the device to its **original state** using the SD card backup created in step 3.

### When to Use This

- Device does not boot
- Partitioning or flashing failed
- You want to revert to the original UniFi OS layout

---

### Recovery Steps

1. Boot the device into **recovery mode**
2. Log in via serial console:

```
login: root
password: ubnt
```

3. Insert the SD card containing the backup

4. Restore the full eMMC image:

```bash
dd if=/dev/mmcblk1 of=/dev/mmcblk0 conv=noerror,sync
```

5. Reboot the device:

```bash
reboot
```

---

### Recovery Result

- Original partition table restored
- Original boot image restored
- UniFi OS fully recovered

---

## Final State (After Successful Install)

- Debian **Bookworm**
- Root filesystem on `/dev/mmcblk0p44`
- Boot image replaced with `custom_boot.img`
- Kernel unchanged
- LED control functional via `ck-splash`

