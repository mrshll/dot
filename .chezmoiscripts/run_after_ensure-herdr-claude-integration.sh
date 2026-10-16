#!/usr/bin/env bash
# Claude's Herdr hooks supply the conversation ID required by supervisor refresh.
# Run after settings are applied; the installer preserves other Claude settings.
set -euo pipefail

command -v herdr >/dev/null 2>&1 || exit 0
if ! herdr integration status | grep '^claude: current ' >/dev/null; then
    herdr integration install claude
fi
