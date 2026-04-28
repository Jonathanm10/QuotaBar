---
tracker:
  kind: linear
  api_key: $LINEAR_API_KEY
  project_slug: "1529320f4961"
  active_states:
    - Todo
    - In Progress
    - Rework
    - Merging
  terminal_states:
    - Closed
    - Canceled
    - Cancelled
    - Duplicate
    - Done
polling:
  interval_ms: 5000
workspace:
  root: ~/Perso/symphony-workspaces/quotabar
hooks:
  after_create: |
    git clone --depth 1 https://github.com/Jonathanm10/QuotaBar.git .
    swift package resolve
agent:
  max_concurrent_agents: 2
  max_turns: 20
codex:
  command: codex --config shell_environment_policy.inherit=all app-server
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
    readOnlyAccess:
      type: fullAccess
    networkAccess: true
    excludeTmpdirEnvVar: false
    excludeSlashTmp: false
---

You are working on Linear issue `{{ issue.identifier }}` for QuotaBar.

Issue context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Operate autonomously in the workspace clone created for this issue. Keep work scoped to the issue, do not edit paths outside the provided repository copy, and never commit real tokens, auth exports, provider responses, keychain dumps, or local Codex/Claude credential files.

Default project posture:

- QuotaBar is a small macOS menu bar app built with Swift Package Manager.
- Preserve the lightweight AppKit menu bar shell, SwiftUI popover model, cache-first startup path, and network-free tests.
- Avoid broad rewrites or drive-by dependencies unless the issue explicitly calls for them.
- Use `colgrep` as the primary code search tool when available.
- Prefer focused fixes with regression tests for provider parsing, usage calculations, UI behavior, and packaging scripts.
- GitHub delivery is expected to use inherited `GH_TOKEN` or `GITHUB_TOKEN`; if neither is available, stop after local validation and report the blocker instead of repeatedly retrying push/PR creation.
- Do not treat `gh auth status` alone as authoritative; verify GitHub access with `gh api user`, `gh pr list --repo Jonathanm10/QuotaBar`, and `git ls-remote --heads origin main`.

Validation expectations:

- Run `swift test` for core logic changes.
- Run `swift build` for build, packaging, or app-target changes.
- Run `./Scripts/package_app.sh` when changes affect the app bundle, resources, entitlements, signing inputs, or runtime launch behavior.
- If app behavior changes, include a concrete manual validation note describing the menu bar/popover path that was exercised.
- Tests must stay network-free; use fixtures or mocks instead of live OpenAI or Anthropic calls.

Workflow:

1. Determine the current issue status and follow the matching flow.
2. If the issue is `Todo`, move it to `In Progress` before implementation.
3. Keep a single persistent Linear workpad comment for plan, acceptance criteria, validation, and progress notes.
4. Reproduce or inspect the current behavior before changing code when the issue is a bug.
5. Implement the smallest coherent change that satisfies the issue.
6. Run the required validation and address failures before opening or updating a pull request.
7. Attach the pull request to the Linear issue and move the issue to `In Review` only after validation is green.
8. If blocked by missing required credentials, permissions, network access, or delivery access after local validation is complete, record the blocker in the workpad, leave any recovery artifact paths in the note, move the issue to `In Review`, and stop. Do not keep retrying the same external blocker.
