---
name: secrets-1password
description: >
  Use when handling secrets, credentials, API tokens, or environment variables
  that need to be injected from 1Password. Trigger on any mention of `op`,
  1Password, `op://` references, `.env` files with secret values, or when a
  command needs credentials that shouldn't touch disk or shell history.
  Explains how to use `passh run` safely instead of `op` directly.
---

# Secrets & 1Password

Use `passh`, not `op`, for every secret operation. Never commit secrets.

`passh` runs the 1Password CLI wherever the biometrics actually are. On the Mac
it calls the local `op`. On serveserve there is no usable biometric prompt —
the 1Password app there throws its auth dialog onto a GUI session nobody is
watching — so `passh` sends the call back to the Mac, where Touch ID appears in
front of the human.

Bare `op` on serveserve fails with `cannot connect to 1Password app`. That is
expected, not a bug to work around. Use `passh`.

## Injecting secrets into a command

Always prefer `passh run`. It resolves `op://` references and puts the values
in the child process's environment via `execve`, so they never touch disk,
shell history, any process's argv, or this conversation:

```bash
passh run --env-file=<(cat <<'EOF'
SOME_TOKEN=op://Dynamical/some-item/SOME_FIELD
EOF
) -- some-command
```

For a single variable the inline form is fine:

```bash
passh run --env-file=<(echo 'MY_TOKEN=op://Dynamical/some-item/credential') -- some-command
```

Add `--account upstreamtech` for work-vault items; the default account is
personal (`my`).

## Do not print secrets

Never use `passh read`, `op read`, or `op item get` to pull a secret into the
terminal. The value lands in the transcript and in scrollback. `passh read`
exists for scripting, not for you. If you need to prove a secret resolved,
check its length (`${#VAR}`), never its value.

## How it reaches the Mac, and when it can't

On serveserve, `passh` talks to `127.0.0.1:18340`. That port is a
`RemoteForward` carried by the SSH session the human opened from their Mac, and
it reaches a small daemon (`passhd`) running there under launchd.

When there is no tunnel — the human is on a phone SSH client, their Mac is
asleep, or (easy to miss) this `tmux` session has outlived the SSH session that
carried the forward — `passh` falls back to running `op` here instead, and says
so on stderr.

**That fallback authenticates with the human's 1Password password, not Touch
ID.** If you see `You are not currently signed in`, stop and tell them to run
`eval $(op signin)` in their own shell. Never attempt to supply, guess, or
prompt for that password yourself, and never put it in a command line.

Failure modes:

- `cannot connect to 1Password app` — you used bare `op`. Use `passh`.
- `no tunnel to the laptop ... Falling back` — expected on mobile or a
  disconnected Mac. Not an error by itself; keep going unless it then reports
  not being signed in.
- `You are not currently signed in` — the human must run `eval $(op signin)`.
  Say so and stop.
- `the Mac rejected our token` — `~/.config/passh/token` drifted from the Mac's
  copy. The human needs to re-copy it.
- A few seconds' pause on first use is Touch ID waiting on the Mac.
  Authorization is cached until the 1Password app relocks, so later calls are
  instant. If it hangs much longer, a prompt is sitting unanswered on their
  Mac — say so rather than retrying in a loop.

Run `passh doctor` to see mode, tunnel reachability, and which accounts are
reachable.

## Blocked on purpose

On the tunnel path `passh` refuses `service-account`, `signin`, `signout`,
`account add`, `account forget`, `update`, and `completion`. `passhd` refuses
them again on the Mac, which is the enforcement that counts — the client runs
on the machine being protected against, so its checks are only a convenience.
The fallback path does not block them, since local `op` protects nothing that
running `op` directly would not already expose.

These would let anyone with shell access on the server mint a durable
credential or repoint the CLI at another account, defeating the point: no
long-lived 1Password credential exists on serveserve. If you genuinely need
one, do it on the Mac by hand.
