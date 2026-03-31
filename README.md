# dot

Dotfiles managed by [chezmoi](https://www.chezmoi.io/), syncing a Mac workstation and an Ubuntu server (`serveserve.local`).

## Quick start

**New Mac:**

```bash
git clone git@github.com:mrshll/dot.git ~/workspace/dot
cd ~/workspace/dot
./setup/install.sh    # or: brew bundle install --file=Brewfile
./setup/secrets.sh    # provision pond .env (1Password or interactive)
./setup/apply.sh      # chezmoi init + apply
```

**New Linux server:**

```bash
git clone git@github.com:mrshll/dot.git ~/workspace/dot
cd ~/workspace/dot
./setup/install.sh
./setup/secrets.sh
./setup/apply.sh
```

**Day-to-day sync (all machines at once):**

```bash
./setup/sync.sh
```

This pulls, commits local changes, installs missing packages (`Brewfile` on Mac, `install.sh` on Linux), pushes, runs `chezmoi apply` locally, then SSHes into each remote and does the same.

## What's managed

| Target | Source | Notes |
|--------|--------|-------|
| `~/.config/nvim/` | `dot_config/nvim/` | LazyVim |
| `~/.config/fish/` | `dot_config/fish/` | Templated — macOS vs Linux PATH |
| `~/.gitconfig` | `dot_gitconfig` | |
| `~/.config/git/ignore` | `dot_config/git/ignore` | |
| `~/.config/btop/btop.conf` | `dot_config/btop/` | |
| `~/.config/gh/config.yml` | `dot_config/gh/` | `hosts.yml` excluded (tokens) |
| `~/.config/kitty/` | `dot_config/kitty/` | Mac-only via `.chezmoiignore` |
| `~/.tmux.conf.local` | `dot_tmux.conf.local` | oh-my-tmux overrides |
| `~/.claude/CLAUDE.md` | `dot_claude/CLAUDE.md` | Universal Claude Code config |

## How it works

**chezmoi** maps source files to home directory targets using naming conventions:
- `dot_` prefix becomes `.` (e.g. `dot_gitconfig` → `~/.gitconfig`)
- `.tmpl` suffix enables Go template rendering (e.g. `config.fish.tmpl`)
- `.chezmoiignore` skips files per-platform (kitty on Linux, etc.)

**Templates** handle machine differences. `.chezmoi.toml.tmpl` detects hostname and OS, then `config.fish.tmpl` uses those to conditionalize PATH setup, aliases, etc.

**oh-my-tmux** is installed by a `run_once_` script on first `chezmoi apply`. Customizations go in `~/.tmux.conf.local`.

## Setup scripts

| Script | Purpose |
|--------|---------|
| `setup/install.sh` | Install core packages — `brew` on Mac, `apt` on Linux |
| `setup/apply.sh` | `chezmoi init` + `apply` (safe to re-run) |
| `setup/secrets.sh` | Provision `~/.config/pond/.env` — 1Password first, interactive fallback |
| `setup/sync.sh` | One command to sync local + all remotes |
| `setup/pull-server.sh` | Pull existing configs from serveserve.local into the repo |

## Secrets

Pond secrets (`~/.config/pond/.env`) are **not** in the repo. `setup/secrets.sh` reads them from a 1Password item ("Pond Secrets" in Personal vault) if `op` is available, otherwise prompts interactively.

## Packages

- **macOS:** `Brewfile` — managed via `brew bundle`
- **Linux:** `setup/install.sh` — data-driven package table with custom installers for `eza`, `bat`, `chezmoi`

## Adding a new config

1. Add the source file under the appropriate `dot_` path
2. If it needs per-machine variation, use a `.tmpl` suffix
3. If it's platform-specific, add an ignore rule in `.chezmoiignore`
4. Run `./setup/sync.sh`

## Remotes

Edit the `REMOTES` array in `setup/sync.sh` to add machines:

```bash
REMOTES=(
    "serveserve.local"
    "user@another-host"
)
```
