---
name: secrets-1password
description: >
  Use when handling secrets, credentials, API tokens, or environment variables
  that need to be injected from 1Password. Trigger on any mention of `op`,
  1Password, `op://` references, `.env` files with secret values, or when a
  command needs credentials that shouldn't touch disk or shell history.
  Explains how to use `op run` safely instead of `op item get`.
---

# Secrets & 1Password

Use the 1Password CLI (`op`) for all secrets. Never commit secrets.

Never use `op item get` — it prints secrets into the terminal and conversation context. Always use `op run` to inject secrets as environment variables into commands. This avoids secrets touching disk or shell history:

```bash
op run --env-file=<(cat <<'EOF'
ENV_VAR_NAME=op://vault/item/field
EOF
) -- some-command
```

For a single variable, the inline form works:

```bash
op run --env-file=<(echo 'MY_TOKEN=op://Private/Some Item/credential') -- some-command
```
