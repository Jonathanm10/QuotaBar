# Contributing To QuotaBar

## Before You Start

QuotaBar is intentionally small. Contributions should preserve that:
- prefer deletion over addition
- keep diffs narrow and reviewable
- reuse existing patterns before introducing abstractions
- avoid new dependencies unless there is a strong, discussed reason

If you want to make a large product or architecture change, open an issue first.

## Development Setup

Requirements:
- macOS 14+
- Swift 6
- Xcode 16 or newer recommended

Core commands:

```bash
swift build
swift test
swift run QuotaBar
```

App bundle packaging:

```bash
./Scripts/package_app.sh
```

## Auth And Test Boundaries

- Live provider refreshes depend on local OAuth state already present on the machine.
- Tests must remain deterministic and must not require live provider credentials.
- Never commit auth files, provider dumps, keychain exports, or screenshots containing tokens or account data.

## What A Good PR Looks Like

Please:
- explain the user-visible problem being solved
- keep changes focused on one concern
- add or update tests for behavior changes
- update docs when setup, behavior, or contribution workflow changes
- run `swift build` and `swift test` before opening the PR

## Style Notes

- Favor straightforward Swift over clever abstraction.
- Keep provider-specific parsing contained to provider modules.
- Preserve the cache-first startup behavior and bounded refresh model unless the PR is explicitly about changing them.
- Prefer network-free tests with fixed fixtures.

## Issues

Bug reports are most useful when they include:
- macOS version
- Swift or Xcode version
- whether the issue affects OpenAI, Anthropic, or both
- reproducible steps
- redacted logs or screenshots when relevant

## Review Expectations

Maintainers may ask contributors to split large PRs, add regression coverage, or trim scope before merge if the change increases complexity without enough payoff.
