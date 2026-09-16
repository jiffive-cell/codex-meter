# Changelog

All notable changes to Codex Meter are recorded here. Release assets and full release notes are published on [GitHub Releases](https://github.com/jiffive-cell/codex-meter/releases).

## [Unreleased]

- Added an MIT license, privacy and security policies, contribution guidance, CI, issue templates, and a pull request template.
- Clarified the local Codex app-server data boundary in the README and privacy documentation.
- Expanded deterministic coverage for protocol parsing, snapshots, freshness, history, reset metadata, and CLI JSON.

## [0.4.0]

The current public release includes:

- native macOS menu bar UI and WidgetKit extension;
- server-returned 5-hour, daily, weekly, and additional quota windows;
- reset-credit counts and expiry metadata when supplied by the service;
- local 30-day usage trend and consumption-rate estimate;
- Chinese/English UI, widget appearance options, refresh settings, and local notifications;
- read-only `codex-meter status --json` output and the Codex Meter Status Skill;
- local build, install, and protocol smoke-test scripts.
