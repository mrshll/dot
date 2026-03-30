#!/usr/bin/env bash
# Provision ~/.config/pond/.env with secrets.
#
# Strategy:
#   1. If 1Password CLI (op) is available and signed in → pull from 1Password
#   2. Otherwise → prompt interactively
#   3. If .env already exists → show what's set and offer to overwrite
#
# 1Password item layout (create once, then this script reads it):
#   Vault: Personal
#   Item:  "Pond Secrets"
#   Fields:
#     GITHUB_TOKEN, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET,
#     ASANA_TOKEN, ASANA_WORKSPACE,
#     TELEGRAM_TOKEN, TELEGRAM_CHAT_ID
#
# To create the item:
#   op item create --category=login --title="Pond Secrets" \
#     --vault=Personal \
#     'GITHUB_TOKEN[password]=ghp_...' \
#     'GOOGLE_CLIENT_ID[text]=...' \
#     'GOOGLE_CLIENT_SECRET[password]=...' \
#     'ASANA_TOKEN[password]=...' \
#     'ASANA_WORKSPACE[text]=...' \
#     'TELEGRAM_TOKEN[password]=...' \
#     'TELEGRAM_CHAT_ID[text]=...'
set -euo pipefail

info()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m==> %s\033[0m\n' "$*"; }
err()   { printf '\033[1;31m==> %s\033[0m\n' "$*" >&2; }

ENV_DIR="$HOME/.config/pond"
ENV_FILE="$ENV_DIR/.env"

OP_VAULT="Personal"
OP_ITEM="Pond Secrets"

# All secret keys and their descriptions (for prompts)
declare -a SECRET_KEYS=(
    "GITHUB_TOKEN"
    "GOOGLE_CLIENT_ID"
    "GOOGLE_CLIENT_SECRET"
    "ASANA_TOKEN"
    "ASANA_WORKSPACE"
    "TELEGRAM_TOKEN"
    "TELEGRAM_CHAT_ID"
)

declare -A SECRET_DESCS=(
    [GITHUB_TOKEN]="GitHub personal access token"
    [GOOGLE_CLIENT_ID]="Google OAuth client ID"
    [GOOGLE_CLIENT_SECRET]="Google OAuth client secret"
    [ASANA_TOKEN]="Asana personal access token"
    [ASANA_WORKSPACE]="Asana workspace GID"
    [TELEGRAM_TOKEN]="Telegram bot token"
    [TELEGRAM_CHAT_ID]="Telegram chat ID"
)

# These keys contain passwords/tokens — mask in output
declare -A SECRET_SENSITIVE=(
    [GITHUB_TOKEN]=1
    [GOOGLE_CLIENT_SECRET]=1
    [ASANA_TOKEN]=1
    [TELEGRAM_TOKEN]=1
)

# --- check existing .env ----------------------------------------------------

mkdir -p "$ENV_DIR"

if [ -f "$ENV_FILE" ]; then
    info "Existing $ENV_FILE found:"
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        key="$(echo "$key" | xargs)"
        if [[ -n "${SECRET_SENSITIVE[$key]:-}" ]]; then
            printf "  %s=%s\n" "$key" "${value:0:4}****"
        else
            printf "  %s=%s\n" "$key" "$value"
        fi
    done < "$ENV_FILE"
    echo

    read -rp "Overwrite? [y/N] " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        info "Keeping existing .env"
        exit 0
    fi
fi

# --- try 1Password ----------------------------------------------------------

declare -A secrets

use_op=false
if command -v op >/dev/null 2>&1; then
    if op account list &>/dev/null; then
        info "1Password CLI detected — attempting to read from '$OP_VAULT/$OP_ITEM'"

        # Test if the item exists
        if op item get "$OP_ITEM" --vault="$OP_VAULT" &>/dev/null; then
            use_op=true
            for key in "${SECRET_KEYS[@]}"; do
                val="$(op read "op://$OP_VAULT/$OP_ITEM/$key" 2>/dev/null || true)"
                if [ -n "$val" ]; then
                    secrets[$key]="$val"
                    info "  $key ✓ (from 1Password)"
                else
                    warn "  $key not found in 1Password — will prompt"
                fi
            done
        else
            warn "Item '$OP_ITEM' not found in vault '$OP_VAULT'"
            warn "Create it with:"
            warn "  op item create --category=login --title='$OP_ITEM' --vault='$OP_VAULT' \\"
            warn "    'GITHUB_TOKEN[password]=...' 'GOOGLE_CLIENT_ID[text]=...' ..."
            echo
        fi
    fi
fi

# --- prompt for missing secrets ---------------------------------------------

for key in "${SECRET_KEYS[@]}"; do
    if [ -n "${secrets[$key]:-}" ]; then
        continue
    fi

    desc="${SECRET_DESCS[$key]}"
    if [ -n "${SECRET_SENSITIVE[$key]:-}" ]; then
        read -rsp "$desc ($key): " val
        echo
    else
        read -rp "$desc ($key): " val
    fi

    if [ -z "$val" ]; then
        warn "Skipping $key (empty)"
    else
        secrets[$key]="$val"
    fi
done

# --- optional: Google Calendar accounts -------------------------------------

read -rp "Configure Google Calendar accounts? (e.g. personal,work) [leave empty to skip]: " cal_accounts

declare -A cal_ids
if [ -n "$cal_accounts" ]; then
    IFS=',' read -ra accounts <<< "$cal_accounts"
    for acct in "${accounts[@]}"; do
        acct="$(echo "$acct" | xargs)"
        read -rp "  Calendar IDs for '$acct' (comma-separated, e.g. primary,team@group.calendar.google.com): " ids
        cal_ids[$acct]="$ids"
    done
fi

# --- optional: toad paths ---------------------------------------------------

read -rp "Toad diary path (e.g. ~/notes/diary) [leave empty to skip]: " diary_path
read -rp "Toad meeting notes path (e.g. ~/notes/meetings) [leave empty to skip]: " meeting_path

# --- write .env --------------------------------------------------------------

info "Writing $ENV_FILE"

cat > "$ENV_FILE" << ENVEOF
# Pond secrets — generated by dot/setup/secrets.sh
# Do not commit this file.

# GitHub
GITHUB_TOKEN=${secrets[GITHUB_TOKEN]:-}

# Google OAuth
GOOGLE_CLIENT_ID=${secrets[GOOGLE_CLIENT_ID]:-}
GOOGLE_CLIENT_SECRET=${secrets[GOOGLE_CLIENT_SECRET]:-}

# Asana
ASANA_TOKEN=${secrets[ASANA_TOKEN]:-}
ASANA_WORKSPACE=${secrets[ASANA_WORKSPACE]:-}

# Telegram (Dawn bot)
TELEGRAM_TOKEN=${secrets[TELEGRAM_TOKEN]:-}
TELEGRAM_CHAT_ID=${secrets[TELEGRAM_CHAT_ID]:-}
ENVEOF

# Append calendar accounts if configured
if [ -n "$cal_accounts" ]; then
    {
        echo ""
        echo "# Google Calendar"
        echo "GOOGLE_CALENDAR_ACCOUNTS=$cal_accounts"
        for acct in "${!cal_ids[@]}"; do
            upper="$(echo "$acct" | tr '[:lower:]' '[:upper:]')"
            echo "GOOGLE_CALENDAR_${upper}_IDS=${cal_ids[$acct]}"
        done
    } >> "$ENV_FILE"
fi

# Append optional toad paths
if [ -n "$diary_path" ] || [ -n "$meeting_path" ]; then
    {
        echo ""
        echo "# Toad paths"
        [ -n "$diary_path" ] && echo "TOAD_DIARY_PATH=$diary_path"
        [ -n "$meeting_path" ] && echo "TOAD_MEETING_NOTES_PATH=$meeting_path"
    } >> "$ENV_FILE"
fi

chmod 600 "$ENV_FILE"

echo
info "Done. Secrets written to $ENV_FILE"
if [ "$use_op" = true ]; then
    info "Secrets sourced from 1Password where available."
else
    info "Tip: store these in 1Password for automatic provisioning next time."
    info "See the comments at the top of this script for the op item create command."
fi
