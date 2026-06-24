# AI Box

Run **Claude Code** and **Codex** inside isolated, persistent Docker containers — one
self-contained Bash script. Linux and macOS only.

Each tool gets its own container image and a Docker named volume that holds its login and
caches, so you authenticate **once per tool**. AI Box itself never reads or stores your
credentials.

## Install

One line, Linux and macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/aaronmgn/aibox/main/install.sh | bash
```

This clones AI Box to `~/aibox`, symlinks `~/.local/bin/aibox` onto your `PATH` (offering to
update your shell rc if needed), and writes default settings under `config/` (gitignored).
Building container images is deferred until you first run a tool. Set `AIBOX_DIR=<path>` to
install somewhere else.

Prefer to inspect first? Do it by hand — the git checkout *is* the install location:

```sh
git clone https://github.com/aaronmgn/aibox.git ~/aibox && ~/aibox/aibox
```

Requires: Docker (Desktop, Colima, OrbStack, or native Engine) and `git`.

## Usage

```sh
aibox                    # interactive menu
aibox claude             # run Claude Code in the current directory
aibox codex              # run Codex in the current directory
aibox --update           # update AI Box (git pull) and rebuild advice
aibox --reset <tool>     # rebuild a tool's image, KEEP its volume (stay logged in)
aibox --wipe <tool>      # remove a tool's image AND volume (lose login); add --yes to skip prompt
aibox --status           # images, volumes, versions
aibox --doctor           # diagnostics
aibox --uninstall        # tiered removal
aibox --help | --version
```

`<tool>` is `claude` or `codex`.

## Workspace

The directory you run `aibox` from is bind-mounted to `/workspace` inside the container, and
the tool starts there. **The agent can read, modify, and delete files in that directory** —
run AI Box from the project you intend to work on.

## Authentication (once per tool, persisted in the volume)

- **Claude Code** — inside the container run `claude setup-token` (or `claude` then `/login`).
  Open the printed URL in your browser, authorize, and paste the token back. Stored under
  `~/.claude/` on the `aibox-claude-home` volume.
- **Codex** — inside the container run `codex` and choose **"Sign in with Device Code"**
  (or `codex login --device-auth`). Open the URL on any device and enter the code. Stored at
  `~/.codex/auth.json` on the `aibox-codex-home` volume.

Both use no inbound port, so they work in the headless container. Re-login is only needed
after `--wipe`.

## How it works

- **Disposable containers**: every launch is `docker run --rm`; the named volume is the
  single source of truth for state. No long-lived containers to drift.
- **Shared base image** (`aibox-base`) + one image per tool (`aibox-claude`, `aibox-codex`).
- CLIs are installed under `/opt` and symlinked onto `PATH` so the home volume never shadows
  or pins them.
- An entrypoint remaps the container user to your host UID/GID so files written in
  `/workspace` stay editable on the host.

## Reset vs. wipe

- **Reset** rebuilds the tool image and **keeps** the volume → fix a broken/stale image or
  apply updated Docker files; you stay logged in.
- **Wipe** removes the image **and** the volume → clean slate; you must log in again.

Both are idempotent and safe to run repeatedly.
