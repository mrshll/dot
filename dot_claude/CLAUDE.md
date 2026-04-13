# Universal Guidelines

## Plans

When working on a plan, always create a branch and draft PR. Store the plan as a markdown file in `./plans/` (repo root), prefixed by the PR number (e.g. `plans/123_add_feature_b.md`). Always use this in-repo method — do not rely on conversation-level planning alone.

Use the plan as a living document. Mark items complete as work progresses. Append new sections as a log with an ISO 8601 date header (e.g. `### 2026-04-02 — PR feedback`) so the plan accumulates context over time — review feedback, revised scope, follow-up steps, etc. When the plan is complete, append a brief retro as the final entry.

## Think Before Coding

Don't assume. Don't hide confusion. Surface tradeoffs.

- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## Goal-Driven Execution

Transform requests into verifiable success criteria so I can loop independently until the goal is met.

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan with a verification step per item:

```
1. [step] → verify: [check]
2. [step] → verify: [check]
```

## Code style

Write code that explains itself. Add only extremely minimal comments and no docstrings unless I ask, but don't remove existing comments. Meaningful variable names over documented code.

Simplicity is paramount. Always look for ways to simplify. Use existing utilities and approaches in the codebase rather than creating new code. Don't add unnecessary abstractions, error handling, or ceremony.

Don't write error handling unless I ask for it. Don't smooth over exceptions unless they are expected control flow. Write code that raises early if something is unexpected.

All functions should have return types defined. Use strict types — interfaces for object shapes, proper generics where applicable.

Follow existing patterns in the codebase. Match the style, structure, and conventions already established before introducing anything new.

## Surgical Changes

Touch only what I asked for. Every changed line should trace directly to my request.

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- If you notice unrelated dead code, mention it — don't delete it.
- Remove imports/variables/functions that *your* changes made unused. Don't remove pre-existing dead code unless asked.

## Python

Always use `uv run` for all Python commands. Never use bare `python`, `python3`, or `pip`. This applies to running scripts, tests, and any Python tooling.

Use `ruff` for linting and formatting.

Always annotate types on all function arguments and return types.

Timestamps are always UTC-aware.

## Go

Use red/green TDD: write a failing test first, then implement the code to make it pass.

Run the full test suite (`go test ./...`) after every code change.

## Testing

Always run the full test suite after code changes.

Document and use single-test execution when debugging (e.g., `uv run pytest tests/test_file.py::test_name`, `go test -run TestName ./...`).

## Communication

Be concise. Match my brevity. Don't restate what I said — just do it. Don't summarize what you just did at the end of every response, I can read the diff.

When I say "commit and push" that's a single atomic action — do both.

When outputting CLI commands for the user to run, always format them as a single line with no indentation. This makes them easy to copy and paste directly into a terminal.

## Validation

Always validate against official documentation where possible.

After visual/frontend changes, verify with a screenshot if Playwright is available.

## Prior art

Before implementing something new, check ~/workspace for analogous patterns in existing projects. If a similar problem has been solved before, follow that approach rather than inventing a new one.

### Dynamical.org — weather data platform

| Project | Stack | Description |
|---------|-------|-------------|
| `dynamical.org` | 11ty/Nunjucks | Static site and dataset catalog |
| `dynamical-py` | Python | Client library (`pip install dynamical`) |
| `reformatters` | Python | Reformat weather datasets into Zarr/Icechunk |
| `ops` | TS/Python | Zarr proxy worker + integration tests |
| `scorecard-backend` | Python | Forecast verification scoring engine |
| `asos-parquet` | Python | Global airport weather obs as GeoParquet |
| `ecmwf-ifs-backfill` | Python | Stage ECMWF IFS archive from MARS to S3 |
| `dynamical-site-data` | Python | Fetch/benchmark data for the website |
| `dynamical-meta` | Python | GitHub project board bidirectional sync |
| `notebooks` | Jupyter | Example notebooks for dynamical.org datasets |

### Upstream Tech

| Project | Stack | Description |
|---------|-------|-------------|
| `mono` | JS/Python/Go | Lens product monorepo (frontend + backend) |
| `upstream.tech` | 11ty/Nunjucks | Lens marketing website |

### Personal

| Project | Stack | Description |
|---------|-------|-------------|
| `pond` | Go | Personal OS: task manager (toad), update inbox (dawn) |
| `vid` | Go/Python | Weather data video generator with retro CRT effects |
| `mmx` | Lua/Shell | Minimal static site generator (powers mrshll.com) |
| `mrshll.github.io` | HTML | Personal website/blog (generated by mmx) |
| `wiki` | Markdown | Personal wiki (mmx-powered) |
| `urth` | React/Python | Workflow visualization platform |
| `hrönir` | Python | Hydro forecast model testing (Chronos, TiRex) |
| `dot` | Shell/chezmoi | Dotfiles |

## Secrets & 1Password

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

## Infrastructure

- Server: serveserve.local (100.72.11.128 via Tailscale), Ubuntu
- Dotfiles: chezmoi, managed from ~/workspace/dot
- Shell: fish on all machines

## Dotfiles edits

Never edit applied dotfiles in place (e.g. `~/.claude/*`, `~/.config/nvim/*`, `~/.gitconfig`). Always edit the chezmoi source in `~/workspace/dot/` (e.g. `dot_claude/`, `dot_config/nvim/`) and then run `~/workspace/dot/setup/sync.sh` to commit, push, and apply across all machines. Editing the applied copy gets clobbered on the next `chezmoi apply` and never reaches the server.
