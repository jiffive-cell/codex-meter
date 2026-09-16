# Security policy

## Scope

Codex Meter is a read-only macOS menu bar app, WidgetKit extension, CLI, and bundled Skill. The repository currently supports the `main` branch and the latest tagged release, currently `0.4.x`. Older releases are not guaranteed to receive security fixes.

The most important security boundary is the local Codex process: Codex Meter starts the locally installed `codex app-server` and sends the `initialize` notification followed by the read-only `account/rateLimits/read` request over standard input/output. Codex Meter does not open or parse `auth.json`, and it does not store or forward Codex tokens. The Codex process remains responsible for its own authentication and service communication.

## Reporting a vulnerability

Please use [GitHub's private vulnerability reporting](https://github.com/jiffive-cell/codex-meter/security) when it is available for this repository. Do not disclose a vulnerability in a public Issue or pull request.

If private reporting is not enabled, contact the maintainer through the repository owner's GitHub profile and include **Security report** in the subject. Share only the minimum reproduction details needed to validate the issue.

Please do not attach:

- `auth.json`, access tokens, cookies, or other credentials;
- prompts, conversation transcripts, project files, or private source code;
- unredacted Codex responses or complete application logs.

For an actionable report, include the affected version or commit, macOS version, Codex version, reproduction steps, expected behavior, and the smallest redacted log or response sample that demonstrates the problem.

## What to expect

The maintainer will acknowledge a report when it can be reproduced, assess its impact, and publish a fix or mitigation in a release when appropriate. Timelines depend on severity and whether the issue depends on the separately installed Codex executable.

## Release and local-build limitations

The current local build is ad-hoc signed and is not notarized. Release artifacts should use Developer ID signing, notarization, and checksums. The local WidgetKit build mirrors a minimal snapshot into the widget container because the ad-hoc build does not use a provisioned App Group; a signed distribution should use a protected App Group container.
