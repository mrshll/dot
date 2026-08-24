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

`passh` is a wrapper around the 1Password CLI that runs `op` wherever the
biometrics actually are. On the Mac it calls the local `op`. On serveserve
there is no usable biometric prompt — the 1Password desktop app there throws
its auth dialog onto a GUI session nobody is looking at — so `passh` forwards
the call over SSH to the Mac, where Touch ID appears in front of the human.

Bare `op` on serveserve fails with `cannot connect to 1Password app`. That is
expected. Use `passh`.

## Injecting secrets into a command

Always prefer `passh run`. It resolves `op://` references and puts the values
in the child process's environment. They never touch disk, shell history, or
this conversation:

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

## When it fails

- `cannot connect to 1Password app` — you used bare `op`. Use `passh`.
- `ssh: FAILED` from `passh doctor` — the Mac is asleep, off the tailnet, or
  Remote Login is off. Nothing on the server can fix this; ask the human.
- Hangs for a few seconds on first use — that is Touch ID waiting on the Mac.
  Authorization is cached until the 1Password app relocks, so subsequent calls
  are instant.

Run `passh doctor` to see mode, connectivity, and which accounts are reachable.

## Blocked on purpose

`passh` refuses `service-account`, `signin`, `signout`, `account add`,
`account forget`, `update`, and `completion`. These would let anyone with
shell access on the server mint a durable credential or repoint the CLI at
another account, which defeats the point: no long-lived 1Password credential
is stored on serveserve. If you genuinely need one, do it on the Mac by hand.
