# Privacy

Codex Meter is designed to display Codex quota state without reading the content of a user's work.

## Data flow

Codex Meter does not make direct HTTP requests. It launches the locally installed `codex` executable with:

```text
codex app-server --listen stdio://
```

It sends the app-server protocol's `initialize` request and the read-only `account/rateLimits/read` request, then uses the returned rate-limit data to update the menu bar UI, local snapshot, widget, and CLI output. The locally installed Codex process handles authentication and any communication with its service. This project cannot make promises about behavior of a separately installed or modified Codex executable.

Codex Meter itself does not:

- open or parse `auth.json`;
- read prompts, conversations, project files, or task content;
- send analytics or telemetry;
- upload files to a third-party endpoint;
- execute Codex tasks, write account state, or redeem reset credits.

## Local data

The app stores only the information needed for the local surfaces to work:

| Data | Location / use | Retention |
| --- | --- | --- |
| Latest quota snapshot | `~/Library/Application Support/CodexMeter/widget-snapshot.json`; rendered by the app, CLI, and widget | Until replaced or removed |
| Trend samples | `~/Library/Application Support/CodexMeter/history.json` | Up to 30 days and 2,000 samples |
| Preferences | macOS `UserDefaults` | Until the user clears the app's preferences |
| Widget mirror | The WidgetKit extension container for the local ad-hoc build | Until replaced or removed |

Snapshots contain quota windows, plan label, reset-credit metadata when supplied, timestamps, and derived local trend values. The widget reads a snapshot; it never starts Codex itself.

The CLI command `codex-meter status --json` reads the latest snapshot and writes JSON to standard output. It does not start Codex or mutate local snapshot state.

## User controls and removal

Use **Settings → Clear history** to remove trend history. To remove the latest snapshot and widget mirror as well, quit Codex Meter and delete the `CodexMeter` application-support directory and the app's WidgetKit container from the current macOS user account. Uninstalling the app does not automatically remove user preferences or those local files.

## Third-party services and affiliation

The application has no analytics provider or third-party upload service. The separately installed Codex process may communicate with OpenAI or other services according to its own implementation and account configuration. Codex Meter is an independent open-source project and is not affiliated with or endorsed by OpenAI.
