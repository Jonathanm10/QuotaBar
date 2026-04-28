#!/usr/bin/env bash
set -euo pipefail

SYMPHONY_DIR="${SYMPHONY_DIR:-$HOME/Perso/symphony}"
SYMPHONY_REPO="${SYMPHONY_REPO:-https://github.com/openai/symphony.git}"

if ! command -v git >/dev/null 2>&1; then
  echo "error: git is required" >&2
  exit 1
fi

if ! command -v mise >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install mise
  else
    echo "error: mise is required and Homebrew is not available" >&2
    echo "install mise, then rerun this script" >&2
    exit 1
  fi
fi

if [ ! -d "$SYMPHONY_DIR/.git" ]; then
  mkdir -p "$(dirname "$SYMPHONY_DIR")"
  git clone "$SYMPHONY_REPO" "$SYMPHONY_DIR"
else
  git -C "$SYMPHONY_DIR" pull --ff-only
fi

cd "$SYMPHONY_DIR/elixir"
mise trust
mise install
mise exec -- mix setup
mise exec -- mix build

echo "Symphony is ready at $SYMPHONY_DIR/elixir"

