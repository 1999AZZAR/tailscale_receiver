# Optimization Notes

The Go rewrite (v3.1.0) resolves the original issues:

| Concern | Bash (legacy) | Go (current) |
|---|---|---|
| Resource usage | Subprocess per check | Single process |
| Reliability | `trap` flaky under load | Signal.NotifyContext |
| Poll overhead | `tailscale status` + `find` | JSON check only |
| Binary size | N/A (script) | ~6MB static |
| Error handling | Silent failures | Preflight + structured errors |
| Archive | Every cycle | Once per hour |
| Notifications | `sudo` incompatible with hardening | Credential syscall |
