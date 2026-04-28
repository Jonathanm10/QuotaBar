#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW_FILE="${WORKFLOW_FILE:-$REPO_ROOT/WORKFLOW.md}"
SYMPHONY_DIR="${SYMPHONY_DIR:-$HOME/Perso/symphony}"
PORT="${PORT:-4000}"
GITHUB_REPO="${GITHUB_REPO:-Jonathanm10/QuotaBar}"
KEYCHAIN_SERVICE="${LINEAR_KEYCHAIN_SERVICE:-llmusage.symphony.linear}"
KEYCHAIN_ACCOUNT="${LINEAR_KEYCHAIN_ACCOUNT:-QuotaBar Symphony}"
GITHUB_KEYCHAIN_SERVICE="${GITHUB_KEYCHAIN_SERVICE:-llmusage.symphony.github}"
GITHUB_KEYCHAIN_ACCOUNT="${GITHUB_KEYCHAIN_ACCOUNT:-QuotaBar Symphony}"
UNGUARDED_FLAG="--i-understand-that-this-will-be-running-without-the-usual-guardrails"

if [ ! -d "$SYMPHONY_DIR/elixir" ]; then
  echo "error: Symphony is not installed at $SYMPHONY_DIR" >&2
  echo "run ./Scripts/symphony_bootstrap.sh first" >&2
  exit 1
fi

if ! command -v mise >/dev/null 2>&1; then
  echo "error: mise is required" >&2
  exit 1
fi

missing=0

if [ -z "${LINEAR_API_KEY:-}" ] && command -v security >/dev/null 2>&1; then
  if token="$(security find-generic-password -w -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" 2>/dev/null)"; then
    export LINEAR_API_KEY="$token"
  fi
fi

if [ -z "${GH_TOKEN:-}" ] && [ -z "${GITHUB_TOKEN:-}" ] && command -v security >/dev/null 2>&1; then
  if token="$(security find-generic-password -w -s "$GITHUB_KEYCHAIN_SERVICE" -a "$GITHUB_KEYCHAIN_ACCOUNT" 2>/dev/null)"; then
    export GH_TOKEN="$token"
    export GITHUB_TOKEN="$token"
  fi
fi

if [ -z "${LINEAR_API_KEY:-}" ]; then
  echo "error: LINEAR_API_KEY is not set and no token was found in macOS Keychain" >&2
  echo "store it once with ./Scripts/symphony_store_linear_token.sh" >&2
  missing=1
fi

if grep -q 'TODO_SET_LINEAR_PROJECT_SLUG' "$WORKFLOW_FILE"; then
  echo "error: replace TODO_SET_LINEAR_PROJECT_SLUG in $WORKFLOW_FILE" >&2
  missing=1
fi

if [ "$missing" -ne 0 ]; then
  exit 1
fi

if { [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; } && command -v gh >/dev/null 2>&1; then
  gh auth setup-git -h github.com >/dev/null 2>&1 || {
    echo "warning: gh auth setup-git failed; gh may work but git push may still lack credentials" >&2
  }
fi

github_preflight_failed=0

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh is required for PR creation" >&2
  github_preflight_failed=1
elif ! gh api user --jq .login >/dev/null 2>&1; then
  echo "error: gh cannot call the authenticated GitHub API" >&2
  echo "run ./Scripts/symphony_store_github_token.sh, or repair gh auth before starting Symphony" >&2
  github_preflight_failed=1
fi

if ! git -C "$REPO_ROOT" ls-remote --heads origin main >/dev/null 2>&1; then
  echo "error: git cannot reach origin/main on GitHub" >&2
  github_preflight_failed=1
fi

if ! gh pr list --repo "$GITHUB_REPO" --limit 1 --json number >/dev/null 2>&1; then
  echo "error: gh cannot access pull requests for $GITHUB_REPO" >&2
  github_preflight_failed=1
fi

if [ "$github_preflight_failed" -ne 0 ] && [ "${SYMPHONY_SKIP_GITHUB_PREFLIGHT:-0}" != "1" ]; then
  echo "refusing to start Symphony because GitHub delivery preflight failed" >&2
  echo "set SYMPHONY_SKIP_GITHUB_PREFLIGHT=1 to start anyway" >&2
  exit 1
fi

if [ "${SYMPHONY_PREFLIGHT_ONLY:-0}" = "1" ]; then
  echo "Symphony preflight passed."
  exit 0
fi

cd "$SYMPHONY_DIR/elixir"
if [ "${SYMPHONY_ACCEPT_UNGUARDED_PREVIEW:-1}" = "1" ]; then
  exec mise exec -- ./bin/symphony "$WORKFLOW_FILE" --port "$PORT" "$UNGUARDED_FLAG"
fi

exec mise exec -- ./bin/symphony "$WORKFLOW_FILE" --port "$PORT"
