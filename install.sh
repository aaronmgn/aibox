#!/bin/sh
#
# AI Box installer — clones (or updates) the AI Box checkout and runs first-run setup.
# POSIX sh; works on Linux and macOS.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/aaronmgn/aibox/main/install.sh | bash
#
# Env overrides:
#   AIBOX_DIR=<path>    install location (default: $HOME/aibox)
#   AIBOX_REPO=<url>    source repo (default: the public AI Box repo)
set -eu

REPO_URL="${AIBOX_REPO:-https://github.com/aaronmgn/aibox.git}"
INSTALL_DIR="${AIBOX_DIR:-$HOME/aibox}"

say() { printf '%s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

os="$(uname -s)"
case "$os" in
  Linux|Darwin) ;;
  *) die "Unsupported OS: $os. AI Box supports Linux and macOS only." ;;
esac

command -v git >/dev/null 2>&1 || \
  die "git is required but was not found. Install git, then re-run this command."

if [ -d "$INSTALL_DIR/.git" ]; then
  say "Updating existing AI Box checkout at $INSTALL_DIR ..."
  git -C "$INSTALL_DIR" pull --ff-only
elif [ -e "$INSTALL_DIR" ]; then
  die "$INSTALL_DIR already exists and is not an AI Box checkout.
       Move it aside, or set AIBOX_DIR=<dir> to install elsewhere."
else
  say "Cloning AI Box into $INSTALL_DIR ..."
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

# First-run setup: creates config, symlinks ~/.local/bin/aibox, offers PATH setup
# (prompts via /dev/tty so it still works through this pipe), then prints diagnostics.
"$INSTALL_DIR/aibox" --doctor

say ""
say "AI Box installed at $INSTALL_DIR"
say ""
say "  Run it with:   aibox            (if ~/.local/bin is on your PATH)"
say "  or directly:   $INSTALL_DIR/aibox"
say ""
say "  Then log in once per tool (see the README \"Authentication\" section):"
say "    aibox claude   ->  claude setup-token"
say "    aibox codex    ->  choose \"Sign in with Device Code\""
