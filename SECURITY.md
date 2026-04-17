# Security Policy

## Supported Scope

QuotaBar handles cached usage snapshots and interacts with local OAuth credentials. Reports involving any of the following are in scope:
- credential exposure
- token refresh handling
- accidental persistence of sensitive provider data
- insecure logging of auth or account information
- cache file disclosure issues

## Reporting

Do not publish secrets, tokens, keychain material, or exploit details in a public issue.

If GitHub private vulnerability reporting is enabled for the repository, use it. Otherwise, open a minimal public issue requesting a private reporting channel and omit all sensitive details until a maintainer responds.

## Disclosure Expectations

- redact tokens, account IDs, and personal data from all reports
- provide the smallest reproducible description that demonstrates impact
- allow time for investigation and a fix before broad disclosure when practical

## Out Of Scope

The following are usually out of scope unless they create a concrete security impact in QuotaBar itself:
- provider-side outages or bugs
- unsupported local machine modifications
- issues that require committing real secrets into the repository to reproduce
