# 🔧 Repurposing UniFi Cloud Key Gen2

A collection of manuals, scripts, and notes for repurposing the **UniFi Cloud Key Gen2** into a flexible Linux-based utility device.

This repository documents practical modifications, system tweaks, and custom tooling to extend the life and capabilities of the Cloud Key hardware.

---

## 📦 Contents

### 🗂 Backup & Automation
- **rsync snapshot backup script**
  - SSH-based incremental backups
  - Hard-link snapshots (`--link-dest`)
  - Retention management
  - Configurable excludes
  - Optional Telegram notifications

---

### 🌐 Networking

- **WireGuard Client Setup**
  - Install and configure WireGuard
  - Persistent tunnel configuration
  - Auto-start on boot
  - Routing and DNS considerations

---

### 💡 Hardware Control & Monitoring

- **LED Control**
  - How to control the front LED
  - Change color / disable LED
  - Use LED for status indication

- **Battery Monitoring**
  - Check internal battery charge level
  - Detect charging status
  - Determine power source (PoE / USB-C / battery)
  - Monitor health and runtime

---

## 🎯 Goals of This Repository

- Extend hardware lifespan
- Provide clean, minimal, reproducible setups
- Keep documentation simple and practical
- Avoid unnecessary bloat
- Make the Cloud Key usable beyond UniFi Controller duties

---

## 🧰 Device Overview

The UniFi Cloud Key Gen2 is essentially:
- ARM-based Linux device
- Internal battery
- PoE-powered
- eMMC storage
- RGB status LED

With proper configuration, it can serve as:

- Backup endpoint
- VPN client
- Monitoring node
- Remote management tool
- Lightweight automation host

---

## 📚 Documentation Structure

Each topic has its own directory with:

- Step-by-step instructions
- Required commands
- Configuration examples
- Troubleshooting notes

Example structure:

```
backup/
wireguard/
led-control/
battery-monitoring/
```

---

## ⚠ Disclaimer

These modifications are unofficial.

You are responsible for:
- Your data
- Your hardware
- Your network security

Proceed carefully and always keep backups.

---

## 🤝 Contributions

Improvements, fixes, and additional documentation are welcome.

If you discover better methods, optimizations, or additional hardware capabilities — feel free to open a pull request.

---

## 📄 License

Add a license of your choice (MIT recommended for documentation/scripts).

---

> Repurpose hardware. Reduce waste. Build useful things.
