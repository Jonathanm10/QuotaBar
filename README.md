# QuotaBar

QuotaBar is a native macOS menu bar app for keeping an eye on OpenAI and Anthropic usage without opening either web dashboard.

It renders:
- daily usage
- weekly usage
- reserve headroom
- reset timing
- pace hints based on the active window

The implementation stays intentionally small:
- AppKit-led menu bar shell
- SwiftUI popover content
- cache-first startup path
- bounded background refresh every 5 minutes
- existing local OAuth session reuse instead of a custom auth flow

## Status

QuotaBar is early-stage but usable. The codebase is small, the tests are fast, and the project is open to focused contributions that keep the app lean.

This project is not affiliated with, endorsed by, or maintained by OpenAI or Anthropic. Provider names and logos remain the property of their respective owners.

## Install

Download the latest signed and notarized DMG from the [Releases page](https://github.com/Jonathanm10/QuotaBar/releases/latest), open it, and drag `QuotaBar.app` to `/Applications`.

Releases are cut from `v*` git tags — pushing `vX.Y.Z` triggers the release workflow, which signs with Developer ID, notarizes via App Store Connect API key, staples, and uploads the DMG.

### Cutting a release

One-time setup:

1. Export your Developer ID Application certificate from Keychain Access as a `.p12` with a password.
2. Mint an App Store Connect API key at https://appstoreconnect.apple.com/access/integrations/api with the `Developer` role (enough for notarization). Download the `AuthKey_XXXXXXXXXX.p8` — it can only be downloaded once.
3. Configure the same key locally so [`asc`](https://github.com/rorkai/App-Store-Connect-CLI) can validate it against your account before you ever push a tag:
   ```bash
   asc auth login \
     --name quotabar-release \
     --key-id YOUR_KEY_ID \
     --issuer-id YOUR_ISSUER_ID \
     --private-key ~/Downloads/AuthKey_YOUR_KEY_ID.p8 \
     --network
   asc auth doctor
   ```
4. Populate the 5 repo secrets:
   ```bash
   base64 -i DeveloperID.p12        | gh secret set DEVELOPER_ID_APPLICATION_CERT_P12_BASE64
   gh secret set DEVELOPER_ID_APPLICATION_CERT_P12_PASSWORD
   gh secret set APPLE_TEAM_ID
   base64 -i AuthKey_YOUR_KEY_ID.p8 | gh secret set ASC_API_KEY_P8_BASE64
   gh secret set ASC_API_KEY_ID
   gh secret set ASC_API_ISSUER_ID
   ```

Then cut a release by pushing a tag:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

## Platform And Tooling

- macOS 14 or newer
- Swift 6 toolchain
- Xcode 16 or newer recommended for local development

## How Auth Works

QuotaBar does not ask contributors to provision new app credentials.

- OpenAI usage is read from an existing local Codex/OpenAI OAuth session, currently sourced from `~/.codex/auth.json` and refreshed into the macOS keychain.
- Anthropic usage is read from the macOS keychain entry used by Claude Code.
- API key-only flows are intentionally out of scope for now.

If those local sessions do not exist, the app can still build and tests will still pass, but live refreshes will fail until valid local credentials are present.

## Local Data Handling

- Cached snapshots are stored under the current user's Application Support directory in `QuotaBar/snapshots.json`.
- Refreshed OAuth credentials are stored in the macOS keychain.
- The repo should never contain real tokens, auth exports, or provider responses copied from a live machine.

## Quick Start

```bash
swift build
swift test
swift run QuotaBar
```

## Package As An App

```bash
./Scripts/package_app.sh
open QuotaBar.app
```

## Development Notes

- `Daily` is derived locally from the current day's delta in each provider's weekly utilization and resets at local midnight.
- The provider-native short window is still fetched and kept as fallback metadata during refresh.
- Reserve is sourced from OpenAI credits balance and Anthropic extra-usage remaining when available.
- Each metric line exposes provenance such as `oauth` or `cache`.
- Tests are expected to stay network-free.

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md).

High-signal contributions for this repo:
- bug fixes with regression tests
- UI polish that preserves the current lightweight menu bar model
- provider parsing hardening for schema drift
- documentation and contributor-experience improvements

Please avoid drive-by dependency additions or broad rewrites before discussing them in an issue.

## Security

Read [SECURITY.md](SECURITY.md) before reporting credential-handling bugs or token leaks.

## License

This project is released under the [MIT License](LICENSE).
