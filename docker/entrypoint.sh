#!/usr/bin/env bash
#
# AI Box container entrypoint.
#
# Runs as root, remaps the 'aibox' user to the host's UID/GID (passed via
# HOST_UID/HOST_GID), makes the volume-backed home writable, then drops
# privileges and execs the requested command (the tool CLI by default).
#
# Why: files the agent writes into the bind-mounted /workspace then carry the
# host user's ownership, so they stay editable on the host (matters on Linux;
# a harmless no-op on macOS where Docker maps ownership for you).
set -e

USER_NAME="aibox"
HOST_UID="${HOST_UID:-1000}"
HOST_GID="${HOST_GID:-1000}"

cur_uid="$(id -u "$USER_NAME")"
cur_gid="$(id -g "$USER_NAME")"

if [ "$cur_gid" != "$HOST_GID" ]; then
  groupmod -o -g "$HOST_GID" "$USER_NAME" 2>/dev/null || true
fi
if [ "$cur_uid" != "$HOST_UID" ]; then
  usermod -o -u "$HOST_UID" "$USER_NAME" 2>/dev/null || true
fi

# Ensure the (volume-backed) home is owned by the possibly-remapped user.
# Recurse only when the top-level owner doesn't already match — this fixes a
# freshly seeded volume (and the rare host-UID-change case) without paying for a
# recursive chown on every warm start.
if [ "$(stat -c %u /home/aibox 2>/dev/null || echo -1)" != "$HOST_UID" ]; then
  chown -R "$HOST_UID:$HOST_GID" /home/aibox 2>/dev/null || true
fi

export HOME="/home/aibox"
export USER="$USER_NAME"
export LOGNAME="$USER_NAME"

if [ "$#" -eq 0 ]; then
  set -- bash
fi

# Drop privileges (setpriv ships with util-linux, always present on Debian).
exec setpriv --reuid "$HOST_UID" --regid "$HOST_GID" --init-groups -- "$@"
