# 🔧 Repurposing UniFi Cloud Key Gen2

A practical collection of notes and scripts for turning the **UniFi Cloud Key Gen2** into a lightweight (~5W) remote backup node.

This repository focuses on simple, reproducible modifications to extend the hardware beyond UniFi Controller use.

---

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

---

> Repurpose hardware. Reduce waste. Build useful systems.
