# AI Box

Run **Claude Code** and **Codex** in isolated, persistent Docker containers — one
self-contained Bash script. Linux and macOS.

Each tool gets its own image and named volumes for its login and caches, so you
authenticate **once per tool**. AI Box never reads or stores your credentials.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/aaronmgn/aibox/main/install.sh | bash
```

Clones AI Box to `~/aibox`, symlinks `~/.local/bin/aibox` onto your `PATH`, and writes
defaults under `config/` (gitignored). Images build on first use. Set `AIBOX_DIR=<path>`
to install elsewhere, or clone by hand — the checkout *is* the install:

```sh
git clone https://github.com/aaronmgn/aibox.git ~/aibox && ~/aibox/aibox
```

Requires Docker (Desktop, Colima, OrbStack, or Engine) and `git`.

## Usage

```sh
aibox                    # interactive menu
aibox claude             # run Claude Code in the current directory
aibox codex              # run Codex in the current directory
aibox --update           # update AI Box (git pull)
aibox --reset <tool>     # rebuild image, keep volumes (stay logged in)
aibox --wipe  <tool>     # remove image + volumes (lose login); --yes skips the prompt
aibox --status           # images, volumes, versions
aibox --diagnostics      # environment diagnostics
aibox --uninstall        # tiered removal
aibox --help | --version
```

`<tool>` is `claude` or `codex`.

## Workspace

The directory you run `aibox` from is bind-mounted at `/workspace/<full-host-path>`
(e.g. `~/Projects/api` → `/workspace/Users/you/Projects/api`), and the tool starts there.
The full path is mirrored so Claude and Codex keep per-project memory separate — even
folders that share a name. **The agent can read, modify, and delete files there**, so run
AI Box from the project you intend to work on.

## Mode

Tools launch in bypass-permission ("yolo") mode — Claude with
`--dangerously-skip-permissions`, Codex with `--yolo` — so they run without approval
prompts. That's appropriate because each tool is confined to its container and the single
workspace directory you mounted.

## Sharing host credentials

Paths listed in `config/mounts.conf` are bind-mounted **read-only** into the container's
home so tools can use your existing credentials. `.ssh` (git over SSH) and `.config/gh`
(GitHub CLI token) are shared by default; uncomment or add more — `.aws`, `.kube`,
`.gitconfig`, … one `$HOME`-relative path per line. The first time a path is actually
shared, AI Box asks you to confirm once (then remembers).

> ⚠️ The agent runs in bypass-permission mode with network access, so it can **read** a
> shared SSH key or token and send it anywhere. Only share paths you trust it with; comment
> a line out to stop sharing it.

## Authentication (once per tool)

- **Claude Code** — in the container run `claude setup-token` (or `claude` then `/login`),
  open the URL, paste the token back. Stored under `~/.claude/`.
- **Codex** — in the container run `codex` and choose **"Sign in with Device Code"** (or
  `codex login --device-auth`), open the URL, enter the code. Stored at `~/.codex/auth.json`.

Both work headless (no inbound port). Re-login is only needed after `--wipe`.

## Storage

Each tool has two named volumes:

- `aibox-<tool>-config` — login, settings, per-project memory. Sticky: survives `--update`
  and `--reset`; only `--wipe` clears it.
- `aibox-<tool>-home` — general home/caches. Clear it on its own with
  `docker volume rm aibox-<tool>-home` to reset working state while staying logged in.

**Reset** rebuilds the image and keeps both volumes (you stay logged in). **Wipe** removes
the image and both volumes (full clean slate; log in again). Both are idempotent.

## How it works

- Every launch is `docker run --rm`; the named volumes are the only state.
- Shared base image (`aibox-base`) + one image per tool (`aibox-claude`, `aibox-codex`).
- CLIs live under `/opt` and are symlinked onto `PATH`, so the home volume never shadows
  them.
- The entrypoint remaps the container user to your host UID/GID, so files written in
  `/workspace` stay editable on the host.
- Commits and PRs the agents make aren't attributed to Claude/Codex as a co-author —
  baked into the images as a managed/system setting (`/etc/claude-code/managed-settings.json`,
  `/etc/codex/config.toml`), so it survives the config volumes.
