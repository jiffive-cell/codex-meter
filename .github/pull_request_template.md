## What changed?

<!-- Summarize the focused problem and the smallest change that solves it. -->

## Verification

- [ ] `swift test`
- [ ] `swift build`
- [ ] `./scripts/build-app.sh` (when app packaging is affected)
- [ ] `./scripts/smoke-test.sh` (when protocol behavior is affected and a signed-in Codex environment is available)

If a check could not run, explain why:

## Privacy and security review

- [ ] No credentials, prompts, conversations, project files, or unredacted logs are included.
- [ ] No new network or telemetry behavior was added without documentation.
- [ ] Read-only account behavior is preserved.

## Documentation and compatibility

- [ ] README/privacy/security/release notes were updated if behavior or data flow changed.
- [ ] Existing `status --json` fields keep their meaning, or the compatibility impact is documented.
