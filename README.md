# 🔧 CloudKey Repurposed – Remote Backup & NAS Node

A practical collection of notes and scripts for turning the **UniFi Cloud Key Gen2** into a lightweight (~5W) remote backup node.

This repository focuses on simple, reproducible modifications to extend the hardware beyond UniFi Controller use.

---


## Getting Started

Before applying the modifications in this repository, make sure the Cloud Key is updated to the latest firmware.

SSH access must be enabled from the UniFi OS web interface. When enabling SSH from the UI, you set the root password there.

Default SSH user:

- `root`

Login example:

```bash
ssh root@<cloudkey-ip>
```

After logging in, follow the instructions in this repository to convert the device into a minimal backup node.



## 📦 What’s Included

### 🗂 Backup Script
- rsync-based backups over SSH to CloudKey
- Incremental snapshot support (`--link-dest`)
- Retention handling
- Remote push configuration

### 🌐 Networking
- WireGuard client configuration
- Persistent tunnel setup
- Auto-start on boot

### 📂 SMB (Samba)
- Secure share for `/volume1/backup`
- Dedicated restricted user
- Writable backup target
- Logging fully disabled (no eMMC writes)

### 💡 Hardware
- LED control
- Battery status monitoring (charge level, power source, health)

### 🖥 System Customization
- Replaced default vendor login banner
- Custom MOTD reflecting device purpose
- Disabled persistent journald storage (RAM-only logging to reduce eMMC wear)

---

## 🎯 Goals

- Extend hardware lifespan
- Keep setup minimal and practical
- Avoid unnecessary complexity
- Repurpose instead of discard

---

## ⚠ Disclaimer

These modifications are unofficial.  
You are responsible for your data, hardware, and network security.
