# Tailscale Receiver — TODO

## Completed (v3.1.0)

- [x] Go rewrite — single static binary, no shell dependencies
- [x] `signal.NotifyContext` for graceful shutdown
- [x] JSON-based tailscale status check before `file get`
- [x] Preflight checks at startup (tailscale binary, target user validity)
- [x] `--once` mode for one-shot execution / systemd timer mode
- [x] `--version` flag
- [x] Configurable via CLI flags + environment variables + `/etc/default/tailscale-receive`
- [x] Archive management throttled to once per hour (not every poll cycle)
- [x] `notify-send` via `SysProcAttr.Credential` (no `sudo` needed, works with `NoNewPrivileges=true`)
- [x] `os.Chown` receiver files instead of shelling out to `chown`
- [x] Systemd service hardened: `PrivateTmp`, `ProtectSystem=strict`, `NoNewPrivileges`, `CapabilityBoundingSet`, etc.
- [x] CI with Go build, vet, fmt check, race detection, and integration tests

## Pending

- [ ] Go unit tests with mocked tailscale CLI
- [ ] Nautilus/Dolphin integration scripts (send-side)
- [ ] Prometheus metrics endpoint (optional)
- [ ] Optional systemd timer deployment mode (alternative to daemon)
