---
name: codex-meter-status
description: Read the current Codex Meter quota, reset credits, consumption rate, and estimated exhaustion time from the local read-only snapshot when the user asks how much Codex capacity remains.
---

# Codex Meter Status

Use this skill for questions such as “我还有多少额度？” or “How many Codex resets do I have?”.

Run the read-only command and parse its JSON output:

```bash
codex-meter status --json
```

If the command is not on `PATH`, try the bundled helper:

```bash
"/Applications/Codex Meter.app/Contents/Helpers/codex-meter" status --json
```

Report the service-returned plan name, every returned limit window’s remaining and used
percentages, reset time, available reset count, and (when present) recent consumption rate
and estimated exhaustion time. Translate the result to the user’s language, but do not rename
or reinterpret an unknown plan tier. Do not estimate a number of messages, read credentials or
conversation content, start a Codex task, or redeem a reset credit.

Always surface `updatedAt` and say when `stale` is `true` (the snapshot is older than 30
minutes). If no snapshot exists, explain that Codex Meter must be opened and allowed to refresh
once; never invent a quota value. A command failure is a monitoring error, not evidence that
the account has no remaining quota.
