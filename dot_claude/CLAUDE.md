# Universal Guidelines

## Scope discipline

Do exactly what I ask — no more. Don't add refactors, style changes, dependencies, or "improvements" beyond the task. If something adjacent looks wrong, mention it — don't fix it. When I say "stop," stop immediately.

Do not change text content, copy, or configuration unless explicitly asked.

## Code style

Write code that explains itself. Add only extremely minimal comments and no docstrings unless I ask, but don't remove existing comments. Meaningful variable names over documented code.

Simplicity is paramount. Always look for ways to simplify. Use existing utilities and approaches in the codebase rather than creating new code. Don't add unnecessary abstractions, error handling, or ceremony.

Don't write error handling unless I ask for it. Don't smooth over exceptions unless they are expected control flow. Write code that raises early if something is unexpected.

All functions should have return types defined. Use strict types — interfaces for object shapes, proper generics where applicable.

Follow existing patterns in the codebase. Match the style, structure, and conventions already established before introducing anything new.

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

## Validation

Always validate against official documentation where possible.

After visual/frontend changes, verify with a screenshot if Playwright is available.

## Infrastructure

- Server: serveserve.local (100.72.11.128 via Tailscale), Ubuntu
- Secrets: 1Password CLI (`op`), never commit secrets
- Dotfiles: chezmoi, managed from ~/workspace/dot
- Shell: fish on all machines
