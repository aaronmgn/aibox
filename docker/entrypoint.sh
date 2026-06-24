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

# Never run the agent as root inside the container, even if aibox was invoked as
# root on the host — otherwise the privilege drop below is a no-op and the agent
# could write root-owned files onto the bind-mounted workspace.
[ "$HOST_UID" = "0" ] && HOST_UID=1000
[ "$HOST_GID" = "0" ] && HOST_GID=1000

cur_uid="$(id -u "$USER_NAME")"
cur_gid="$(id -g "$USER_NAME")"

if [ "$cur_gid" != "$HOST_GID" ]; then
  groupmod -o -g "$HOST_GID" "$USER_NAME" 2>/dev/null || true
fi
if [ "$cur_uid" != "$HOST_UID" ]; then
  usermod -o -u "$HOST_UID" "$USER_NAME" 2>/dev/null || true
fi

# Ensure volume-backed dirs are owned by the (possibly remapped) user. Recurse
# only when the top-level owner doesn't already match, so warm starts stay cheap.
# /home/aibox and the tool's config dir can be backed by independent volumes that
# may be freshly seeded (root-owned) at different times, so own each separately.
ensure_owned() {
  dir="$1"
  [ -n "$dir" ] || return 0
  mkdir -p "$dir" 2>/dev/null || true
  if [ "$(stat -c '%u:%g' "$dir" 2>/dev/null || echo -1)" != "$HOST_UID:$HOST_GID" ]; then
    chown -R "$HOST_UID:$HOST_GID" "$dir" 2>/dev/null || true
  fi
}
ensure_owned /home/aibox
ensure_owned "${AIBOX_CONFIG_DIR:-}"

# Own the intermediate parent dirs of any read-only shares. Docker pre-creates
# them (e.g. /home/aibox/.config for a .config/gh mount) as root before this
# runs, and the warm-start optimization above may skip the recursive chown — so
# own each explicitly (non-recursive; never touches the read-only mount itself).
if [ -n "${AIBOX_OWN_DIRS:-}" ]; then
  _oifs="$IFS"; IFS=':'
  for _d in $AIBOX_OWN_DIRS; do
    [ -n "$_d" ] || continue
    chown "$HOST_UID:$HOST_GID" "$_d" 2>/dev/null || true
  done
  IFS="$_oifs"
fi

export HOME="/home/aibox"
export USER="$USER_NAME"
export LOGNAME="$USER_NAME"

if [ "$#" -eq 0 ]; then
  set -- bash
fi

# Drop privileges (setpriv ships with util-linux, always present on Debian).
exec setpriv --reuid "$HOST_UID" --regid "$HOST_GID" --init-groups -- "$@"
