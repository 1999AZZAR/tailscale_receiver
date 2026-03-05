# Tailscale Receiver v3 (Go) 🚀

Tailscale File Receiver yang beneran stable, reliable, dan irit resource. Dibuat buat gantiin versi shell script lama yang boros proses.

## ✨ Kenapa Versi Go?
- **Low Resource**: Memory usage cuma **~2MB**. Jauh lebih enteng dibanding shell script.
- **Reliable**: Handle sinyal shutdown secara graceful (nggak ada file korup/nanggung).
- **Smart Polling**: Cek status Tailscale via JSON API sebelum narik file.
- **Single Binary**: Nggak butuh dependensi eksternal macem-macem.

## 🛠️ Cara Install & Pakai
1. Clone repo:
   ```bash
   git clone https://github.com/1999AZZAR/tailscale_receiver
   cd tailscale_receiver
   ```
2. Build & Install otomatis:
   ```bash
   chmod +x install-go.sh
   ./install-go.sh
   ```
3. Nyalain service-nya:
   ```bash
   sudo systemctl enable --now tailscale-receive-go
   ```

## ⚙️ Konfigurasi
Edit file `/etc/default/tailscale-receive` buat atur variabel berikut:
- `TARGET_DIR`: Folder tujuan file (default: `~/Downloads/tailscale`).
- `TARGET_USER`: User pemilik file hasil download.
- `POLL_INTERVAL`: Jeda antar pengecekan (default: `15s`).
- `ARCHIVE_DAYS`: Simpan file lama selama X hari di folder `archive/` (default: `14`).

## 📜 Legacy Version
Versi shell script yang lama udah dipindahin ke folder `legacy/` kalau kamu masih butuh buat referensi.

---
*Maintained with ❤️ by Mema (Multi-Euristic Mind Automaton)*
