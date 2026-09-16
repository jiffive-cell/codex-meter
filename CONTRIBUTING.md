# Contributing to Codex Meter

Thank you for helping improve a small, privacy-conscious open-source tool for Codex users.

## Before you start

- Read [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).
- Search existing Issues and pull requests before opening a new one.
- Never include credentials, `auth.json`, prompts, conversations, project files, or unredacted logs in an Issue or pull request.
- For a security vulnerability, use the private reporting route in [SECURITY.md](SECURITY.md), not a public Issue.

## Development requirements

- macOS 14 or newer;
- Swift 6 or Xcode Command Line Tools;
- Xcode when working on the full WidgetKit/AppIntent build;
- a signed-in Codex environment only when running the local protocol smoke test.

The project has no external Swift package dependencies. Open the repository root before running the commands below.

## Verify a change

Run the deterministic checks first:

```bash
swift test
swift build
```

When the local Codex executable is installed and signed in, also run:

```bash
./scripts/build-app.sh
./scripts/smoke-test.sh
```

The smoke test starts the local Codex app-server and requests rate limits. It is intentionally not part of CI because it requires a user's local authentication environment.

## Pull requests

Keep changes focused and preserve the existing read-only behavior. A good pull request should:

1. explain the user-visible or maintenance problem;
2. describe the smallest change that solves it;
3. add or update deterministic tests for core logic;
4. include documentation changes when data flow, CLI output, installation, or release behavior changes;
5. report the commands run and any local-only checks that could not run;
6. avoid unrelated formatting or product changes.

Please do not change the `status --json` schema without documenting the compatibility impact. Prefer additive fields and preserve existing field meanings.

## Issues

For bug reports, include macOS version, Codex version, Codex Meter version or commit, reproduction steps, and a redacted `status --json` shape when relevant. Feature requests should explain the user problem and why the request remains compatible with a read-only monitor.

## Releases

Maintainers should update `Resources/Info.plist`, `Resources/WidgetInfo.plist`, the host version metadata, README, and [CHANGELOG.md](CHANGELOG.md); run tests/build/smoke checks; generate SHA-256 hashes for release assets; and publish a new immutable `vX.Y.Z` tag. Release assets must state whether they are ad-hoc signed, Developer ID signed, and notarized.

Contributions are accepted under the [MIT License](LICENSE).
