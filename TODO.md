## Tailscale Receiver — TODO and Enhancements

This document tracks proposed improvements for robustness, security, maintainability, and UX. Items are organized by category and prioritized.

### Legend

- Priority: High (H), Medium (M), Low (L)
- Effort: Small (S), Medium (M), Large (L)

### Summary Table

| Done | ID | Category      | Item                               | Why                                    | How (Implementation Hints)                                                                                                                                                                                                                                                                                                                                                                                              | Priority | Effort |
| ---- | -- | ------------- | ---------------------------------- | -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------ |
| [ ]  | 1  | Security      | Systemd sandboxing                 | Reduce blast radius if compromised     | In unit file: `PrivateTmp=true`, `ProtectSystem=strict`, `ProtectHome=yes`, `ReadWritePaths=/home/USER/Downloads/tailscale`, `NoNewPrivileges=true`, `ProtectHostname=true`, `ProtectClock=true`, `ProtectControlGroups=true`, `ProtectKernelTunables=true`, `RestrictSUIDSGID=true`, `LockPersonality=true`, `RestrictRealtime=true`, `SystemCallFilter=@system-service @file-system` (tune), `CapabilityBoundingSet=` | H        | M      |
| [ ]  | 2  | Security      | Drop interactive `tailscale up`    | Avoid hanging service / auth in daemon | Remove auto `tailscale up` from loop; require pre-auth via CLI or use `TS_AUTHKEY` via EnvironmentFile; detect lack of auth and log/retry quietly                                                                                                                                                                                                                                                                       | H        | S      |
| [ ]  | 3  | Security      | Secrets handling                   | Avoid secrets in unit file             | Support `/etc/default/tailscale-receive` (root:root 600). Read `TS_AUTHKEY`, config via `EnvironmentFile=`                                                                                                                                                                                                                                                                                                              | H        | S      |
| [ ]  | 4  | Security      | Validate inputs                    | Defensive against misconfig            | Validate TARGET_DIR existence, writable; verify `id "$FIX_OWNER"` before use; refuse `root` as target user unless `--allow-root`                                                                                                                                                                                                                                                                                        | M        | S      |
| [ ]  | 5  | Security      | Full-path executables              | Avoid PATH confusion                   | Resolve with `TS_BIN=$(command -v tailscale)`; use absolute paths for `ping`, `runuser`, `chown`, `notify-send`                                                                                                                                                                                                                                                                                                         | M        | S      |
| [ ]  | 6  | Reliability   | Strict bash mode                   | Catch errors early                     | Add `set -Eeuo pipefail` and `IFS=$'\n\t'`; add traps for cleanup/logging                                                                                                                                                                                                                                                                                                                                               | H        | S      |
| [ ]  | 7  | Reliability   | Robust new-file detection          | Handle spaces/newlines                 | Avoid `ls`; after `tailscale file get "$TARGET_DIR"`, enumerate with `find -maxdepth 1 -type f -printf '%P\0'` and compare previous set (use state file, sort -z/comm -z)                                                                                                                                                                                                                                               | H        | M      |
| [ ]  | 8  | Reliability   | Backoff strategy                   | Be nice on network failures            | Exponential backoff on ping/tailscale errors (cap e.g. 5 min) instead of fixed 15s                                                                                                                                                                                                                                                                                                                                      | M        | S      |
| [ ]  | 9  | Reliability   | Single-instance guard              | Prevent duplicate loops                | Rely on systemd; also optional PID file lock (flock) to avoid accidental double runs                                                                                                                                                                                                                                                                                                                                    | L        | S      |
| [ ]  | 10 | Reliability   | Handle directories                 | Received dirs not just files           | If `-d` path, chown `-R`, notify with count; test                                                                                                                                                                                                                                                                                                                                                                       | M        | S      |
| [ ]  | 11 | Observability | Structured logging                 | Easier debugging                       | Prefix levels (INFO/WARN/ERR); log to stdout for journald; optionally JSON lines                                                                                                                                                                                                                                                                                                                                        | M        | S      |
| [ ]  | 12 | Observability | Log context                        | Who/what/where                         | Log target user, dir, counts of files, durations; include error codes                                                                                                                                                                                                                                                                                                                                                   | M        | S      |
| [ ]  | 13 | Observability | Health endpoint (optional)         | Ops checks                             | Simple `ExecStartPost` status command or a lightweight `--once` mode for systemd timer checks                                                                                                                                                                                                                                                                                                                           | L        | M      |
| [ ]  | 14 | UX            | Non-interactive install            | Automation friendly                    | Support `NONINTERACTIVE=true TARGET_USER=...`; fail fast if not resolvable                                                                                                                                                                                                                                                                                                                                              | H        | S      |
| [ ]  | 15 | UX            | Preflight checks                   | Clear errors                           | Check for `tailscale`, `notify-send`, systemd presence; print actionable instructions                                                                                                                                                                                                                                                                                                                                   | M        | S      |
| [ ]  | 16 | UX            | Better notifications               | Useful info                            | Notify with number of files, size; throttle if too frequent; include open-folder action where desktop supports                                                                                                                                                                                                                                                                                                          | M        | M      |
| [ ]  | 17 | Packaging     | Environment file                   | Configurable without edits             | `/etc/default/tailscale-receive` with `TARGET_USER`, `TARGET_DIR`, `LOG_LEVEL`, `TS_AUTHKEY`                                                                                                                                                                                                                                                                                                                            | H        | S      |
| [ ]  | 18 | Packaging     | Install using `install(1)`         | Safer perms                            | Use `install -m 0755` for scripts, `-m 0644` for unit/desktop files                                                                                                                                                                                                                                                                                                                                                     | M        | S      |
| [ ]  | 19 | Packaging     | Unprivileged service (if feasible) | Reduce root usage                      | Consider running service as target user and avoid `chown` by writing as user; if tailscale writes as root, keep root but sandbox                                                                                                                                                                                                                                                                                        | M        | L      |
| [ ]  | 20 | Packaging     | Debian/RPM packaging               | Easy deploy                            | Provide `.deb`/`.rpm` with systemd unit, postinst scripts                                                                                                                                                                                                                                                                                                                                                               | L        | L      |
| [ ]  | 21 | Code Quality  | ShellCheck                         | Prevent bugs                           | Add `shellcheck` CI; fix warnings/errors                                                                                                                                                                                                                                                                                                                                                                                | H        | S      |
| [ ]  | 22 | Code Quality  | Tests                              | Confidence                             | Add `bats` tests for functions (user detection, replacement, non-interactive), and integration smoke tests                                                                                                                                                                                                                                                                                                              | M        | M      |
| [ ]  | 23 | Code Quality  | Lint hooks                         | Developer ergonomics                   | Pre-commit with shellcheck, shfmt (non-destructive), trailing whitespace removal                                                                                                                                                                                                                                                                                                                                        | M        | S      |
| [ ]  | 24 | Features      | Configurable polling               | Flexibility                            | `POLL_INTERVAL` env; support `--interval` flag                                                                                                                                                                                                                                                                                                                                                                          | L        | S      |
| [ ]  | 25 | Features      | Systemd timer alternative          | Power saving                           | Replace infinite loop with `OnUnitActiveSec=` timer calling a `--once` mode                                                                                                                                                                                                                                                                                                                                             | M        | M      |
| [ ]  | 26 | Features      | GNOME/Nautilus integration         | Wider DE support                       | Provide `.desktop`/Nautilus action for send script similar to Dolphin                                                                                                                                                                                                                                                                                                                                                   | M        | M      |
| [ ]  | 27 | Features      | Archive management                 | Keep folder tidy                       | Optionally auto-move files older than N days to archive or trash                                                                                                                                                                                                                                                                                                                                                        | L        | M      |

---

### Concrete Task List (with suggested steps)

IDs in parentheses map to the rows in the Summary Table above.

- [ ] (ID 6) Apply strict mode in `tailscale-receive.sh` and guard variables
  
  - Add at top:
    
    ```bash
    set -Eeuo pipefail
    IFS=$'\n\t'
    trap 'echo "[ERR] line $LINENO" >&2' ERR
    ```
  - Quote all variable expansions

- [ ] (ID 7) Replace `ls` diffing with null-safe file set tracking
  
  - Maintain a state file under `/run/tailscale-receive/state` (tmpfs)
  - After `tailscale file get "$TARGET_DIR"`, list filenames using:
    
    ```bash
    mapfile -d '' files_after < <(find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -printf '%P\0')
    ```
  - Compare against prior set using `comm -z`/`sort -z`

- [ ] (ID 2) Remove `tailscale up` from the loop
  
  - Detect unauthenticated state: if `tailscale status` fails, log WARN and sleep/backoff
  - Optionally, if `TS_AUTHKEY` present, try `tailscale up --authkey=$TS_AUTHKEY` once at start

- [ ] (ID 3, 17) Add environment file support
  
  - Create `/etc/default/tailscale-receive` (600) with variables:
    - `TARGET_USER=azzar`
    - `TARGET_DIR=/home/azzar/Downloads/tailscale`
    - `LOG_LEVEL=info`
    - `TS_AUTHKEY=` (optional)
  - In unit file add: `EnvironmentFile=-/etc/default/tailscale-receive`
  - Update install/uninstall to create/remove the file safely

- [ ] (ID 1) Harden systemd unit
  
  - Add:
    
    ```ini
    PrivateTmp=true
    ProtectSystem=strict
    ProtectHome=yes
    ReadWritePaths=/home/%i/Downloads/tailscale
    NoNewPrivileges=true
    ProtectHostname=true
    ProtectClock=true
    ProtectControlGroups=true
    ProtectKernelTunables=true
    RestrictSUIDSGID=true
    LockPersonality=true
    RestrictRealtime=true
    # Tune filters if needed for tailscale CLI access
    SystemCallFilter=@system-service @file-system
    ```
  - Consider templating as `tailscale-receive@.service` so `%i` is the username

- [ ] (ID 5) Resolve binaries at start
  
  - `TS_BIN=$(command -v tailscale || true)` and error if missing
  - Do same for `ping`, `chown`, `runuser`, `notify-send`

- [ ] (ID 16) Improve notifications
  
  - Aggregate if multiple files: "Received N files"
  - Include action: open folder (where supported)
  - Throttle to <= 1 notif / 5s to avoid spam

- [ ] (ID 15) Preflight checks in installer
  
  - Verify tailscale installed; prompt to install if missing
  - Verify desktop notify tool exists (`notify-send`), otherwise skip notif with warning
  - Validate username early; warn if home dir not found

- [ ] (ID 18) Use `install` instead of `cp` in installer
  
  - Receiver: `install -m 0755 "$TMP_SCRIPT" "$DEST_SCRIPT_PATH"`
  - Unit: `install -m 0644 ...`
  - Desktop files: `install -m 0644 ...`

- [ ] (ID 21, 22, 23) CI & linting
  
  - GitHub Actions workflow: run `shellcheck` and `bats` tests on PRs
  - Provide `Makefile` targets: `make install`, `make uninstall`, `make test`

- [ ] (ID 25) Optional: systemd timer alternative
  
  - Create `tailscale-receive.timer` with `OnBootSec=30s` and `OnUnitActiveSec=30s`
  - Service runs once (`/usr/local/bin/tailscale-receive.sh --once`)

- [ ] Document operational modes in README
  
  - Auth via `tailscale up` vs `TS_AUTHKEY`
  - Environment variables and defaults
  - Hardening and known limitations

---

### Notes and Caveats

- Running the service as root simplifies ownership corrections but increases risk; strong sandboxing is recommended if root is required.
- `notify-send` may fail in headless servers without a session bus. Detect `DBUS_SESSION_BUS_ADDRESS`/`DISPLAY` or skip notification with a warning.
- KDE Dolphin service menu is optional; consider separate installer flags for headless/server installs.
- Tailscale CLI behavior can change; prefer pinning minimum version and verifying features you rely on in preflight checks.
