#!/usr/bin/env bash
set -euo pipefail

KEYCHAIN_SERVICE="${GITHUB_KEYCHAIN_SERVICE:-llmusage.symphony.github}"
KEYCHAIN_ACCOUNT="${GITHUB_KEYCHAIN_ACCOUNT:-QuotaBar Symphony}"

if ! command -v security >/dev/null 2>&1; then
  echo "error: macOS security command is required" >&2
  exit 1
fi

printf "GitHub token: "
IFS= read -rs token
printf "\n"

if [ -z "$token" ]; then
  echo "error: empty token" >&2
  exit 1
fi

security add-generic-password \
  -U \
  -s "$KEYCHAIN_SERVICE" \
  -a "$KEYCHAIN_ACCOUNT" \
  -w "$token" >/dev/null

echo "Stored GitHub token in macOS Keychain service '$KEYCHAIN_SERVICE'."

