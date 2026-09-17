# Universal Guidelines

## Plans

When working on a plan for a major change or feature, create a branch and draft PR. The plan lives in the PR description.

While working, keep the plan as a local untracked markdown file in `./plans/` (repo root), prefixed by the PR number (e.g. `plans/123_add_feature_b.md`) — don't commit it. Once the PR is ready, move the plan into the PR description and delete the local file.

Use the plan as a living document. Mark items complete as work progresses. Append new sections as a log with an ISO 8601 date header (e.g. `### 2026-04-02 — PR feedback`) so the plan accumulates context over time. When the plan is complete, append a brief retro as the final entry.

## Think before coding

- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.

## Goal-driven execution

Transform requests into verifiable success criteria. "Add validation" → "write tests for invalid inputs, then make them pass." "Fix the bug" → "write a test that reproduces it, then make it pass."

## Surgical changes

Touch only what I asked for. Every changed line should trace to my request.

- Don't refactor adjacent code, comments, or formatting.
- If you notice unrelated dead code, mention it — don't delete it.
- Remove imports/variables that *your* changes made unused. Don't remove pre-existing dead code unless asked.

## Python

Always use `uv run` — never bare `python`, `python3`, or `pip`.

Use `ruff` for linting and formatting. Annotate types on all function arguments and return types. Timestamps are always UTC-aware.

## Go

Use red/green TDD: write a failing test first, then implement.

Run `go test ./...` after every code change.

## Testing

Run the full test suite after code changes. When debugging, use single-test execution (`uv run pytest tests/test_file.py::test_name`, `go test -run TestName ./...`).

## Communication

Match my brevity. Don't restate what I said — just do it.

"Commit and push" is a single atomic action — do both.

When outputting CLI commands for me to run, format as a single line with no indentation so they're copy-pasteable.

## Secrets

Use `passh`, never bare `op`. It runs the 1Password CLI where the biometrics
are: locally on the Mac, and from serveserve back to the Mac through a tunnel
carried by my SSH session (serveserve's 1Password app throws its auth prompt
onto a GUI nobody watches). Bare `op` on serveserve fails with `cannot connect
to 1Password app` — that's expected.

Inject secrets, never print them:

```bash
passh run --env-file=<(echo 'MY_TOKEN=op://Dynamical/item/field') -- some-command
```

Add `--account upstreamtech` for work vaults. Never use `passh read` or
`op item get` to pull a secret into the terminal — it lands in the transcript.
To prove a value resolved, check `${#VAR}`, not the value.

If `passh` reports no tunnel, it falls back to local `op`, which needs my
1Password *password* rather than Touch ID. On `You are not currently signed
in`, tell me to run `eval $(op signin)` — never try to supply that password
yourself. Don't route around any of this with a service-account token.
`passh doctor` diagnoses the link.

## Infrastructure

- Server: serveserve.local (100.72.11.128 via Tailscale), Ubuntu
- Dotfiles: chezmoi, managed from `~/workspace/dot`
- Shell: fish on all machines

## Dotfiles edits

Never edit applied dotfiles in place (e.g. `~/.claude/*`, `~/.config/nvim/*`, `~/.gitconfig`). Always edit the chezmoi source in `~/workspace/dot/` (e.g. `dot_claude/`, `dot_config/nvim/`) and then run `~/workspace/dot/setup/sync.sh` to commit, push, and apply across all machines.

## Kubernetes: kubectl-readonly-marsh-mutates

Any agent looking at the cluster (pods, jobs, cronjobs, logs, events) must use the read-only context described in [dynamical-eks-3-low-permissions-kubeconfig](#kubernetes-reference-dynamical-eks-3-low-permissions-kubeconfig), never the admin kubeconfig or `AWS_PROFILE=dynamical`. Mutating commands (kubectl apply/create/delete/scale/suspend, `aws iam`, secret rotation, in-cluster jobs) are Marsh's to run: an agent prepares the exact command and hands it to him. Reading a Kubernetes Secret in any form (`kubectl get secret ... -o jsonpath/yaml/json`, `.data`, base64 -d) is forbidden for agents.

**Why:** On 2026-09-17 reform-cape-rename ran `kubectl get secret aws-open-data-icechunk-storage-options-key -o jsonpath='{.data}'` expecting a key listing and printed the AWS access key id and secret into its transcript, forcing a key rotation. The low-permissions ServiceAccount cannot read secrets, exec, or modify anything, so using it makes that class of mistake impossible.

**How to apply:** Put the low-permissions kubeconfig instruction in every orchestrator and helper briefing that may touch the cluster (agents inherit no PATH or kubeconfig; give the absolute path and both flags). When a step needs a mutation, the agent writes the manifest or command and the supervisor relays it to Marsh, as with the EC46 trim job on 2026-09-17. Adding this to herdr-meta prompt.md was proposed and not yet authorized as of 2026-09-17.

## Kubernetes reference: dynamical-eks-3-low-permissions-kubeconfig

Cluster `dynamical-eks-3`, region us-west-2. A `low-permissions` ServiceAccount in `kube-system` is bound to a ClusterRole with get/list/watch on pods, services, endpoints, configmaps, namespaces, nodes, PVs/PVCs, events, deployments/replicasets/statefulsets/daemonsets, jobs/cronjobs, ingresses/networkpolicies, plus get on pods/log. It cannot read secrets, exec into pods, or patch/update/delete anything (tested read-only). It authenticates with a static bearer token, so no IAM, SSO, or 1Password is needed.

Usage, always with both flags explicit (no KUBECONFIG merging or aliases; in fish use a space, not `=`, so the tilde expands):

```
kubectl --kubeconfig ~/.kube/low-permissions.kubeconfig --context low-permissions get pods -n default
```

Setup: an admin (Alden or Marshall, via their own AWS SSO access) runs `aws eks describe-cluster --name dynamical-eks-3 --region us-west-2` for endpoint and CA, pulls the token from secret `low-permissions-token` in kube-system, and builds a kubeconfig with cluster `dynamical-eks-3`, context and user `low-permissions`, namespace default. The kubeconfig is a shared credential: never commit or paste it; revoking one copy means rotating the token for everyone; share it via 1Password only.

Limits: no `kubectl top` (no metrics-server); no scaling, suspending, or deleting jobs. As of 2026-09-17 the file did not yet exist on serveserve; Marsh generates it. Policy for agents: [kubectl-readonly-marsh-mutates](#kubernetes-kubectl-readonly-marsh-mutates).
