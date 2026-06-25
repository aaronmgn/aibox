# AI Box

Run **Claude Code** and **Codex** inside isolated, persistent Docker containers — one
self-contained Bash script. Linux and macOS only.

Each tool gets its own container image and Docker named volumes that hold its login and caches,
so you authenticate **once per tool** and your sessions, settings, and per-project memory persist
across runs. The container is the blast radius: the agent can only touch the single project
directory you launch it from. AI Box itself never reads or stores your credentials.

The base image also ships a set of cloud/Kubernetes/Python CLIs (`kubectl`, `aws`, `uv`, `flux`,
`argo`) so the agents can do real infrastructure work out of the box.

## Requirements

- **Docker** — Docker Desktop, Colima, OrbStack, or native Docker Engine, with the daemon running.
- **git** — used by the installer and by `aibox --update`.
- **OS** — Linux or macOS (Intel or Apple Silicon; the image builds for both `amd64` and `arm64`).

## Install

One line, Linux and macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/aaronmgn/aibox/main/install.sh | bash
```

This clones AI Box to `~/aibox`, symlinks `~/.local/bin/aibox` onto your `PATH` (offering to
update your shell rc if needed), and writes default settings under `config/` (gitignored).
Building container images is deferred until you first run a tool. Set `AIBOX_DIR=<path>` to
install somewhere else, or `AIBOX_REPO=<url>` to install from a fork.

Prefer to inspect first? Do it by hand — the git checkout *is* the install location:

```sh
git clone https://github.com/aaronmgn/aibox.git ~/aibox && ~/aibox/aibox
```

## Quick start

```sh
aibox claude          # builds images on first run, then drops you into Claude Code
# inside the container, log in once:  claude setup-token
```

After the one-time login, `aibox claude` (or `aibox codex`) from any project directory launches
straight into the tool. See [Authentication](#authentication) for the per-tool details.

## Commands

```sh
aibox                    # interactive menu
aibox claude             # run Claude Code in the current directory
aibox codex              # run Codex in the current directory
aibox --update           # update AI Box (git pull) + advise if a rebuild is needed
aibox --reset <tool>     # rebuild a tool's image, KEEP its volumes (stay logged in)
aibox --wipe  <tool>     # remove a tool's image AND volumes (lose login); --yes skips the prompt
aibox --status           # images, volumes, versions
aibox --diagnostics      # environment diagnostics
aibox --uninstall        # tiered removal (symlink/config → images → volumes)
aibox --help | --version
```

`<tool>` is `claude` or `codex`. Each subcommand also has a `--flag` alias (e.g. `--claude`).

## Workspace

The directory you run `aibox` from is bind-mounted at `/workspace/<full-host-path>` inside the
container (e.g. `~/Projects/api` → `/workspace/Users/you/Projects/api`), and the tool starts
there. The full host path is mirrored on purpose: Claude and Codex store memory and metadata
**per working directory**, so giving each project a unique path keeps their histories separate
— even two different folders that happen to share a name. **The agent can read, modify, and
delete files in that directory** — run AI Box from the project you intend to work on.

AI Box refuses to launch from `/` (which would mount your whole filesystem) and prompts for
confirmation before launching from a broad/sensitive root such as `$HOME`, `~/.ssh`, `~/.aws`,
`~/.gnupg`, or `~/.config`.

## Run mode

Tools launch in bypass-permission ("yolo") mode by default — Claude with
`--dangerously-skip-permissions`, Codex with `--yolo` — so they run without stopping for
approval prompts. This is appropriate because each tool is confined to its container and the
single workspace directory you mounted. Any extra arguments you pass are forwarded to the
underlying CLI, e.g. `aibox claude --model opus`.

## Bundled CLIs

The shared base image installs these onto every tool's `PATH` (`/usr/local/bin`):

| CLI | What | Source / version |
|-----|------|------------------|
| `kubectl` | Kubernetes CLI | latest stable from `dl.k8s.io` |
| `aws` | AWS CLI v2 | official self-contained bundle |
| `uv` / `uvx` | Python package & project manager | Astral installer |
| `flux` | FluxCD CLI | FluxCD installer |
| `argo` | Argo Workflows CLI | GitHub release (`ARGO_VERSION` build arg, default `latest`) |

Each reads its own config/credentials from `$HOME` at runtime (`~/.kube`, `~/.aws`,
`~/.config/uv`, …) on the persistent home volume, so contexts and logins survive restarts. They
start empty — to feed them your existing host config, see the next section. `argo` can be pinned
for a reproducible build with `docker build --build-arg ARGO_VERSION=v3.6.2 …`.

## Sharing host credentials

Paths listed in `config/mounts.conf` are bind-mounted **read-only** into the container's home so
tools can use your existing credentials and config. `.ssh` (git over SSH) and `.config/gh`
(GitHub CLI token) are shared by default; uncomment or add more — `.aws`, `.kube`, `.gitconfig`,
`.config/gcloud`, … one `$HOME`-relative path per line (a `#` starts a comment):

```ini
.ssh             # git over SSH (keys, known_hosts)
.config/gh       # GitHub CLI token + host config
# .aws           # AWS credentials/config
# .kube          # kubeconfig
```

- Each path is exposed at the **same spot** in the container home (`.kube` → `/home/aibox/.kube`),
  so the bundled CLIs find it where they expect.
- Mounts are **read-only**. Newly-accepted SSH host keys still persist: the image points
  `UserKnownHostsFile` at a writable `~/.aibox_known_hosts` before your read-only `~/.ssh/known_hosts`.
- The first time a path is actually shared, AI Box asks you to confirm **once**, then remembers.
- Missing paths are skipped silently; absolute paths, `..`, and commas are rejected.

> ⚠️ **Security:** the agent runs in bypass-permission mode with network access, so it can
> **read** a shared SSH key or token and send it anywhere. Only share paths you trust it with;
> comment a line out to stop sharing it. Note that kubeconfigs using exec plugins
> (`aws eks get-token`, `gke-gcloud-auth-plugin`) may need those dependencies available too.

## Authentication

Log in **once per tool**; the credential is saved on that tool's sticky config volume.

- **Claude Code** — inside the container run `claude setup-token` (or `claude` then `/login`).
  Open the printed URL in your browser, authorize, and paste the token back. Stored under
  `~/.claude/` (`CLAUDE_CONFIG_DIR`) on the sticky `aibox-claude-config` volume.
- **Codex** — inside the container run `codex` and choose **"Sign in with Device Code"**
  (or `codex login --device-auth`). Open the URL on any device and enter the code. Stored at
  `~/.codex/auth.json` (`CODEX_HOME`) on the sticky `aibox-codex-config` volume.

Both use no inbound port, so they work in the headless container. Re-login is only needed
after `--wipe`.

## How it works

- **Disposable containers**: every launch is `docker run --rm`; the named volumes are the
  single source of truth for state. No long-lived containers to drift.
- **Shared base image** (`aibox-base`) + one image per tool (`aibox-claude`, `aibox-codex`).
  Tool CLIs are installed under `/opt` and symlinked onto `PATH`, and the bundled CLIs under
  `/usr/local/bin`, so the home volume never shadows or pins them.
- **Privilege drop**: the container starts as root, the entrypoint remaps the `aibox` user to
  your host UID/GID, then drops privileges before exec'ing the tool. Files the agent writes in
  `/workspace` therefore stay owned by you and editable on the host (this matters on Linux; on
  macOS Docker maps ownership for you).
- **No AI attribution**: commits and PRs the agents make aren't attributed to Claude/Codex as a
  co-author. This is baked into the images as a managed/system setting
  (`/etc/claude-code/managed-settings.json`, `/etc/codex/config.toml`), so it survives — and
  takes precedence over — the config volumes.
- **Multi-arch**: the base image builds for `amd64` and `arm64`, detecting the target at build time.

## Storage

Each tool has **two named volumes**:

- `aibox-<tool>-config` — login, settings, and per-project memory. This is the sticky one:
  it survives `--update` and `--reset`, so you don't re-login when AI Box or the image
  changes. (`CLAUDE_CONFIG_DIR` / `CODEX_HOME` point each CLI here.)
- `aibox-<tool>-home` — general home/caches (also where `~/.kube`, `~/.aws`, etc. live unless you
  share them from the host). Clear it on its own with `docker volume rm aibox-<tool>-home` to
  reset working state while staying logged in.

## Reset vs. wipe vs. uninstall

- **Reset** (`aibox --reset <tool>`) rebuilds the tool image and **keeps both volumes** → fix a
  broken/stale image or apply updated Docker files; you stay logged in.
- **Wipe** (`aibox --wipe <tool>`) removes the image **and both volumes** → full clean slate for
  one tool; you must log in again. Add `--yes` to skip the confirmation.
- **Uninstall** (`aibox --uninstall`) is tiered and interactive: (1) remove the script symlink +
  `config/`, keeping images and volumes; (2) also remove AI Box images; (3) remove everything
  including volumes (destroys logins, requires typing `DELETE`). The git checkout itself is left
  in place for you to `rm -rf` if you want.

Reset and wipe are idempotent and safe to run repeatedly.

## Troubleshooting

- **`aibox` not found after install** — `~/.local/bin` isn't on your `PATH`. Open a new shell, or
  add `export PATH="$HOME/.local/bin:$PATH"` to your shell rc. `aibox --diagnostics` reports PATH
  and symlink status.
- **"Docker daemon is not reachable"** — start Docker Desktop/Colima/OrbStack, or on Linux
  `sudo systemctl start docker`. Permission-denied on the socket usually means you're not in the
  `docker` group: `sudo usermod -aG docker "$USER"` then log out/in (avoid `sudo docker`).
- **`apt` "At least one invalid signature was encountered" during build** — a corrupt Docker
  builder cache (or a drifted VM clock after a laptop sleep). Clear it with `docker builder prune`
  and rebuild.
- **Tool changes after an update don't take effect** — `aibox --update` only pulls the script;
  Docker images are rebuilt by `aibox --reset <tool>`. The updater warns when Docker files changed.
- **`--update` refuses to run** — it requires a clean git checkout. Commit or stash local changes
  in the install dir first.

## Project layout

```
aibox                    # the entire CLI (one Bash script)
install.sh               # curl|bash installer (POSIX sh)
VERSION                  # version string
docker/
  Dockerfile.base        # shared Debian base + bundled CLIs + SSH known_hosts shim
  Dockerfile.claude      # Claude Code image (FROM aibox-base) + no-attribution setting
  Dockerfile.codex       # Codex image (FROM aibox-base) + no-attribution setting
  entrypoint.sh          # UID/GID remap + privilege drop
config/                  # gitignored runtime state (created on first run)
CLAUDE.md                # contributor/agent guidance for this repo
```
