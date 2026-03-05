# Tailscale Receiver v3 (Go Edition)

Beneran stable, reliable, dan irit resource.

## Kenapa versi Go?
1. **Low Resource**: Jauh lebih irit RAM dibanding script Bash yang panggil `tailscale`, `find`, `comm`, `chown` berkali-kali tiap cycle.
2. **Reliable**: Pake `signal.NotifyContext` buat graceful shutdown.
3. **Static Binary**: Satu file binary doang, nggak butuh dependensi macem-macem.
4. **Smart Polling**: Cek status Tailscale via JSON sebelum eksekusi `file get`.

## Cara Pakai (Baru)
1. Build & Install: `./install-go.sh`
2. Start: `sudo systemctl enable --now tailscale-receive-go`

## Env Configuration (/etc/default/tailscale-receive)
- `TARGET_DIR`: Folder tujuan (default: `~/Downloads/tailscale`)
- `TARGET_USER`: User pemilik file (default: `$USER`)
- `POLL_INTERVAL`: Jeda antar cycle (default: `15s`)
- `LOG_LEVEL`: Set ke `debug` buat liat detail
- `ARCHIVE_DAYS`: Berapa hari file lama di simpen (default: `14`)

---
*Optimized with ❤️ by Mema*
