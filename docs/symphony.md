# Symphony Setup

This repo is prepared to be driven by OpenAI Symphony through the root `WORKFLOW.md`.

Symphony itself runs from the upstream Elixir implementation, not from this Swift package.
This repo includes helper scripts for the local setup:

```bash
./Scripts/symphony_bootstrap.sh
```

The workflow is configured for the Linear `Maintenance` project in the `QUO` team.

Then store a Linear token once in macOS Keychain:

```bash
./Scripts/symphony_store_linear_token.sh
```

`LINEAR_API_KEY` still works as a temporary override when set in the shell.

Store a GitHub token once too if Symphony workers should push branches and create pull requests:

```bash
./Scripts/symphony_store_github_token.sh
```

The run script exports that token as both `GH_TOKEN` and `GITHUB_TOKEN` for the Symphony process,
then runs `gh auth setup-git -h github.com` so `git push` can use the GitHub CLI credential helper.

Start Symphony with this project's workflow:

```bash
./Scripts/symphony_run.sh
```

The run script preflights GitHub delivery before starting Symphony:

- `gh api user`
- `gh pr list --repo Jonathanm10/QuotaBar`
- `git ls-remote --heads origin main`

Set `SYMPHONY_SKIP_GITHUB_PREFLIGHT=1` only when you intentionally want to run without PR delivery.
Use `SYMPHONY_PREFLIGHT_ONLY=1 ./Scripts/symphony_run.sh` to validate credentials and network without starting Symphony.

The run script passes Symphony's required engineering-preview acknowledgement flag by default.
Set `SYMPHONY_ACCEPT_UNGUARDED_PREVIEW=0` to disable that behavior.

You can override locations and port:

```bash
SYMPHONY_DIR=~/Perso/symphony PORT=4001 ./Scripts/symphony_run.sh
```

Installed locally during setup:

- `mise` via Homebrew.
- Symphony cloned and built at `~/Perso/symphony`.
- Erlang `28` and Elixir `1.19.5-otp-28` via `mise`.

Credential setup:

- A Linear token still needs to be stored with `./Scripts/symphony_store_linear_token.sh`, or provided through `LINEAR_API_KEY`.
- A GitHub token still needs to be stored with `./Scripts/symphony_store_github_token.sh`, or provided through `GH_TOKEN`/`GITHUB_TOKEN`, if workers should push and create pull requests.
