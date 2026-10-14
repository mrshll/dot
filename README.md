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

This first SSHes into each remote to commit and push any edits made there, then pulls, commits local changes, installs missing packages (`Brewfile` on Mac, `install.sh` on Linux), pushes, runs `chezmoi apply` locally, and finally pulls and applies on each remote. A remote that is the current machine is skipped, so the script can run from any listed host; edits applied on a remote are never left uncommitted.

Run it from the Mac: the Mac is not SSH-reachable from the server (Remote Login is off), so a run on serveserve commits, pushes, and applies there but cannot apply on the Mac. Herdr 0.9 draws the sidebar on the viewing client, so Herdr UI changes only show once the Mac has applied them and the client has reloaded its config.

## Herdr desktop (Mac)

Press **Alt+Shift+Enter** or run `herdr-desk` to arrange workspace 6 with
one Kitty window with labeled tabs attached to serveserve's default, dynamical,
and upstream herdr sessions on the left (2/3 width), and toad on the right
(1/3). The tab labels stay visible at the top. Existing launcher windows and
an open toad window are reused.
Use `herdr-desk NUMBER` to choose another workspace; unrelated windows on the
destination are left alone and the launcher exits with an explanation.

**Ctrl+Tab / Ctrl+Shift+Tab** switches herdr tabs; **Alt+L** focuses toad and **Alt+H** returns
to herdr. **Alt+6** returns to this workspace. Run the launcher again after
changing monitors to restore the proportions. Closing Kitty detaches the
herdr clients; remote agents keep running.

## Deskflow (Mac → marshbox)

The keyboard and mouse plugged into the Mac also drive marshbox, on its own
display: [Deskflow](https://github.com/deskflow/deskflow) with the Mac as
server and marshbox as client, TLS on and both fingerprints trusted. marshbox
sits to the right of the Mac (`Library/Deskflow/deskflow-server.conf`).

It's meant for the home LAN only: both ends use the Mac's home LAN address,
never a Tailscale name or 100.x address. The Mac has a DHCP reservation on
the home router. The server listens on that address alone,
read from `~/Library/Deskflow/listen-address`, and marshbox connects to it,
read from `remote-host` beside its Deskflow.conf. Both are uncommitted
one-line files, so the address stays out of this repo. Anything but a
private IPv4 address there (a Tailscale name or 100.x address, a hostname,
nothing at all) falls back to loopback. Away from home the Mac doesn't hold
the address, so the server can't listen (unless another network happens to
hand it the same one; mutual TLS still turns away anything but marshbox).

On the Mac, Deskflow runs only when started by hand: open the app at home
before using it, and quit it before leaving. Nothing starts it at login, so
it never comes up on whatever network the Mac is on. marshbox stays home and
starts its client at login from an XDG autostart entry (Flatpak, since Ubuntu
24.04 has no package). Each app starts its own core.

`modify_Deskflow.conf` owns only the role, name, address and TLS keys; the
app keeps everything else. Quit Deskflow before applying, or the running app
may write its own values back.

marshbox runs the client only inside a graphical session, so its login screen
gets no input from the Mac: log in there with marshbox's own spare keyboard.

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
