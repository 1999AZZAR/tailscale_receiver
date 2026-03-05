# Optimized Tailscale Receiver (WIP)

## Current Issues
1. **Inefficient Polling**: Constant shell execution of `tailscale file get` and `find` every 15s.
2. **Resource Usage**: Bash overhead for heavy logic (integrity, virus scan, rate limiting).
3. **Reliability**: Shell script `trap` and background process management can be flaky for long-running services.

## Optimization Strategy
1. **Reduce Polling Frequency / Move to Events**: Tailscale doesn't support inotify for the internal Taildrop buffer, but we can optimize how we check.
2. **Leaner Logic**: Strip out heavy "enterprise" features (virus scanning, complex rate limiting) if not needed, or make them truly optional and lightweight.
3. **Memory/CPU**: Minimize sub-process spawning.

## Proposed Changes
1. Rewrite core loop to be more "quiet" when idle.
2. Use a more robust language (Go or Rust) if we want true "stable/reliable" but keep it as a simple binary. 
3. *Alternative*: Refactor the Bash script to use `tailscale status --json` for cleaner checks.

## Questions for Azzar
- Do you really need ClamAV (virus scan) and Rate Limiting for a personal receiver?
- Should we consider a Go rewrite for a single static binary? (Much more stable/reliable).
