# CLAUDE.md

Guidance for Claude Code (and other agents) working in this repository.

## What this is

`aibox` runs **Claude Code** and **Codex** inside isolated, persistent Docker containers, so
each tool authenticates once and its state survives across runs. The whole CLI is a single
self-contained Bash script. Targets **Linux and macOS only**.

## Layout

| Path | Role |
|------|------|
| `aibox` | The entire CLI — one Bash script. Almost all changes happen here. |
| `install.sh` | `curl \| bash` installer (POSIX `sh`). Clones/updates the checkout, then runs `aibox --diagnostics`. |
| `docker/Dockerfile.base` | Shared Debian-slim base + bundled CLIs (kubectl, aws, uv, flux, argo) + SSH known_hosts shim. |
| `docker/Dockerfile.claude`, `docker/Dockerfile.codex` | Per-tool images built `FROM aibox-base`; also bake the "don't attribute commits to the AI" settings. |
| `docker/entrypoint.sh` | Remaps the `aibox` user to the host UID/GID, owns shared-mount parent dirs, drops privileges, execs the CLI. |
| `VERSION` | Version string read by `load_version`. Bump on release. |
| `config/` | **Gitignored** runtime state (`aibox.conf`, `mounts.conf`, `state.conf`, `logs/`), created on first run. Never commit. |

There is no automated test suite and no build system — `aibox` *is* the program, run in place.

## Hard constraints (read before editing)

1. **`aibox` must stay Bash 3.2 compatible** (stock macOS `/bin/bash`). No associative arrays,
   no `mapfile`, no `${var,,}`/`${var^^}`, no `readlink -f`. Use the portable idioms already in
   the file (`resolve_self`, `trim_ws`, indexed arrays with the `${arr[@]+"${arr[@]}"}` empty-guard
   under `set -u`). `install.sh` is stricter still: **POSIX `sh`**, no Bash-isms at all.

2. **Install tools to `/opt` or `/usr/local/bin`, never under `/home/aibox`.** At runtime the
   `aibox-<tool>-home` named volume is mounted over `/home/aibox`, shadowing anything installed
   there and pinning stale copies across rebuilds. The tool Dockerfiles install CLIs under
   `/opt` and symlink onto PATH for exactly this reason; the bundled CLIs go to `/usr/local/bin`.

3. **`docker --mount` uses commas as field separators**, so a path containing a comma cannot be
   a bind-mount source. The script rejects comma paths (workspace and shared mounts) — keep that.

4. **Never let the agent run as root in the container.** `entrypoint.sh` remaps `aibox` to
   `HOST_UID`/`HOST_GID` and `setpriv`s down so files written to the bind-mounted `/workspace`
   stay host-editable. A `0` host UID/GID is clamped to `1000`. Don't bypass the entrypoint for
   the main run path (the `volume_has_login` probe deliberately overrides it with `--entrypoint sh`).

5. **Docker build context is `docker/`** (`docker build ... -f docker/Dockerfile.base docker`).
   Dockerfiles can only `COPY` files that live under `docker/`.

## How the runtime fits together

- Every launch is `docker run --rm` (disposable container); **named volumes are the only state.**
- Two volumes per tool:
  - `aibox-<tool>-config` — sticky login/settings/memory. Pointed at by `CLAUDE_CONFIG_DIR`
    (`/home/aibox/.claude`) or `CODEX_HOME` (`/home/aibox/.codex`). Survives `--reset`/`--update`.
  - `aibox-<tool>-home` — general home/caches at `/home/aibox`. The config volume is nested on top.
- The current directory is bind-mounted at `/workspace/<full-host-path>` and is the working dir.
  The full path is mirrored so Claude/Codex keep per-project memory unique per directory.

## Host credential sharing (`config/mounts.conf`)

- `ensure_mounts_config` writes a default `config/mounts.conf` on first run, pre-enabling `.ssh`
  and `.config/gh`. Entries are one `$HOME`-relative path per line; `#` starts a comment.
- `collect_extra_mounts` turns present entries into **read-only** bind mounts at the same path
  under `/home/aibox`, and records intermediate parent dirs in `AIBOX_OWN_DIRS` (colon-joined)
  so the entrypoint can `chown` them (docker pre-creates them root-owned). It blocks textual
  traversal only (`/…`, `..`, `,`); a symlink inside `$HOME` is followed and trusted.
- `maybe_confirm_mounts` asks for consent **once** (then records `mounts_acknowledged=yes` in
  `state.conf`) before exposing credentials to the bypass-permission agent. Keep this gate.
- The SSH known_hosts shim in `Dockerfile.base` points `UserKnownHostsFile` at a writable
  `~/.aibox_known_hosts` first, so accepted host keys persist even when `~/.ssh` is read-only.

## Commit attribution

The tool images bake settings so commits/PRs the agents make are **not** attributed to the AI:
`/etc/claude-code/managed-settings.json` (Claude) and `/etc/codex/config.toml` +
`requirements.toml` (Codex). These live outside the config volumes (and Claude's managed path
takes precedence over `~/.claude`), so the `~/.claude` / `~/.codex` volumes can't shadow them.

## Config vs. state

Both are simple `key=value` files under `config/` (gitignored).
- `aibox.conf` — user settings, read with `get_config KEY [DEFAULT]` (skips comments). Defaults
  written by `write_default_config` only when the file is **absent**, so existing installs won't
  pick up new keys — document new keys, never assume they exist. (Several keys here are currently
  inert placeholders; only wire one up once it actually reads it.)
- `state.conf` — internal state, `get_state`/`set_state` (e.g. `mounts_acknowledged`).
- `mounts.conf` — the host-share list (see above), its own line-based format.

## Build & verify

```sh
bash -n aibox                                                   # syntax check (do this after every edit)
docker build -t aibox-base:latest -f docker/Dockerfile.base docker   # build shared base
aibox --reset claude                                            # rebuild base (cached) + claude image (--no-cache)
aibox --diagnostics                                             # environment diagnostics
aibox --status                                                  # images, volumes, versions
```

The base image is multi-arch: amd64 and arm64, selected via `dpkg --print-architecture` (mapped
to `x86_64`/`aarch64` for the AWS CLI). End each tool install in a Dockerfile with a `--version`
sanity check so a broken install fails the build. To verify a tool runs as the unprivileged user,
run the base image through `entrypoint.sh` with `HOST_UID`/`HOST_GID` set.

Images build lazily on first `aibox <tool>` run; they are **not** rebuilt automatically when a
Dockerfile changes — use `aibox --reset <tool>`.

## Extending

- **Add a bundled CLI:** edit `docker/Dockerfile.base` (install to `/usr/local/bin`, handle both
  arches, end with `<cli> --version`). Rebuild via `aibox --reset <tool>`. Update the README.
- **Add a new AI tool:** add `docker/Dockerfile.<tool>`, then extend in `aibox`: `TOOLS`,
  `validate_tool`, `tool_config_dir`, `tool_config_env`, and `volume_has_login`. Wire it into the
  arg parser and menus. Mirror the `/opt` install + PATH-symlink pattern from the existing tools.
