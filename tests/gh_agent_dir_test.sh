#!/usr/bin/env bash
# Regression test: ~/.config/gh-agent (the agents' gh config, holding
# mrshll-agent's hosts.yml) renders as a private directory. agent-gh --seed
# makes it 0700; if the source said otherwise, the next apply would see a
# change since chezmoi last wrote it and prompt, which a sync's non-TTY apply
# can't answer, stopping the sync.
#
# Usage: tests/gh_agent_dir_test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/dst"
printf '[data]\n  hostname = "test"\n  os = "linux"\n  is_server = true\n  has_op = false\n' > "$WORK/chezmoi.toml"

got=$(chezmoi dump --source "$REPO_DIR" --destination "$WORK/dst" --config "$WORK/chezmoi.toml" \
    --persistent-state "$WORK/state.boltdb" --format json "$WORK/dst/.config/gh-agent" 2>/dev/null |
    jq -r '.[] | select(.type == "dir") | .perm')
if [ "$got" = 448 ]; then
    echo "ok:   .config/gh-agent renders 0700"
    echo; echo "all passed"
else
    printf 'FAIL: .config/gh-agent renders %o, want 700\n' "$got" >&2
    exit 1
fi
