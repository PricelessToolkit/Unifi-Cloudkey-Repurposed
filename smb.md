# 📂 Samba (SMB) Configuration

This device exposes `/volume1/backup` over SMB for controlled remote access.

The configuration is minimal and restricted to a dedicated user.

---

## Install Samba

```bash
sudo apt update
sudo apt install samba
```

Enable and start the service:

```bash
sudo systemctl enable smbd
sudo systemctl start smbd
```

---

## Create SMB User

Create a system user (no shell login required):

```bash
sudo adduser smbuser
```

Add the user to Samba:

```bash
sudo smbpasswd -a smbuser
```

Ensure the backup directory ownership matches:

```bash
sudo chown -R smbuser:smbuser /volume1/backup
sudo chmod -R 0770 /volume1/backup
```

---

## Samba Configuration

Edit:

```bash
sudo nano /etc/samba/smb.conf
```

Add or modify:

```ini
log level = 0
max log size = 50

[backup]
   path = /volume1/backup
   browseable = yes
   writable = yes
   valid users = smbuser
   create mask = 0660
   directory mask = 0770
```

Restart Samba:

```bash
sudo systemctl restart smbd
```

---

## Notes

- `log level = 0` keeps logging minimal (reduced eMMC writes)
- `max log size = 50` limits individual log file size (in KB)
- Access is restricted to `smbuser`
- Permissions enforce group-based control
- Share is writable and intended for controlled backup access only
