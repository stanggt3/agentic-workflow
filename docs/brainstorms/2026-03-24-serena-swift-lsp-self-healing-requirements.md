---
date: 2026-03-24
topic: serena-swift-lsp-self-healing
---

# Serena Swift LSP — Self-Healing Bridge

## Problem Frame

The Swift LSP bridge connects a macOS-native `sourcekit-lsp` process (host) to the
Serena Docker container via a Unix domain socket. The connection breaks in at least
three ways today, requiring manual session restarts:

1. **Session-restart desync** — when `serena-docker` is re-invoked for a new session
   it creates a *new* socket inode; the old container still has the old inode mounted,
   so `connect()` returns ECONNREFUSED.
2. **Startup race** — `sleep 1` is not a reliable signal that socat has created the
   socket file; on a slow machine or under load the Docker container may start before
   the socket exists.
3. **Mid-session crash** — if `sourcekit-lsp` or the host socat dies after a
   successful connection, the shim inside the container exits and Swift LSP silently
   disappears for the rest of the session.

## Requirements

- **R1. Named container eviction** — `serena-docker` assigns every container a stable
  name (`serena-<repo>`). At startup, if a container with that name already exists
  (from a prior session or crash), it is stopped and removed before the new socket and
  container are created. This guarantees the container always holds the current socket
  inode.

- **R2. Socket wait loop** — replace `sleep 1` with a polling loop that waits until
  the socket file actually exists on the host filesystem (up to ~10 s in short
  increments). If the socket never appears within the window, fall back gracefully to
  the standard non-Swift image (existing behaviour).

- **R3. Retry shim** — replace the one-shot `exec socat - UNIX-CONNECT:...` shim in
  `Dockerfile.serena-swift` with a loop that:
  - retries the socket connection with brief back-off at startup (up to ~30 s) so
    a slightly-late socat does not cause a permanent failure;
  - after a successful connection, silently reconnects if the socket closes
    unexpectedly (sourcekit-lsp crash, host socat restart), so Swift LSP recovers
    without the user noticing.

- **R4. Image rebuild required** — because the shim lives inside the Docker image,
  `BUILD_SWIFT=1 ./setup.sh` must be re-run after the `Dockerfile.serena-swift`
  change. This is a prerequisite noted in setup documentation, not a new user-facing
  step.

## Success Criteria

- Starting a new Claude Code session after a prior one left a running Serena container
  does not produce "Connection refused" inside the container.
- If `sourcekit-lsp` crashes mid-session, Swift LSP resumes within ~10 s without a
  manual session restart.
- A host machine under load (socat slow to bind) does not silently fall back to
  non-Swift Serena.
- No new system-level daemons or launchd agents are introduced.

## Scope Boundaries

- No changes to the TCP/socket architecture — the Unix domain socket bridge is kept
  as-is.
- No external watchdog process or launchd plist.
- TypeScript LSP is unaffected; changes are isolated to the Swift bridge path.
- `setup.sh` changes, if any, are limited to documentation or minor script tweaks;
  no new build steps are added.

## Key Decisions

- **Named container over anonymous `--rm`**: gives us the handle needed to evict stale
  containers; `--rm` is retained so the container still cleans up on normal exit.
- **Shim-level retry over container restart policy**: Docker restart policies can't
  remount a new socket inode, so healing must happen at the connection layer inside
  the shim.
- **Silent mid-session reconnect**: users rarely notice a brief Swift LSP gap; a
  visible warning would be noise for an automatic recovery.

## Dependencies / Assumptions

- `socat` and `sourcekit-lsp` are available on the host (already verified in the
  session that diagnosed the bug).
- The `serena-local:latest-swift` image can be rebuilt via `setup.sh`.
- Serena's internal LSP manager handles a brief connection gap gracefully (shim
  reconnects; Serena re-runs LSP init). This is assumed but not verified.

## Outstanding Questions

### Resolve Before Planning
*(none)*

### Deferred to Planning
- [Affects R3][Needs research] Does Serena's Swift LSP manager restart initialization
  automatically when the shim exits and reconnects, or does it mark Swift as
  permanently unavailable after the first disconnect?
- [Affects R3][Needs research] What exit code does `socat` produce on ECONNREFUSED vs
  normal EOF? The retry loop should only loop on connection-failure exits, not on
  clean LSP shutdown.

## Next Steps
→ `/ce:plan` for structured implementation planning
