#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}/.."
CODEX_BIN="${CODEX_BIN:-/Applications/ChatGPT.app/Contents/Resources/codex}"

if [[ ! -x "$CODEX_BIN" ]]; then
  CODEX_BIN="$(command -v codex || true)"
fi
if [[ -z "$CODEX_BIN" || ! -x "$CODEX_BIN" ]]; then
  echo "Codex executable not found" >&2
  exit 1
fi

/usr/bin/python3 - "$CODEX_BIN" <<'PY'
import json, select, subprocess, sys, time

proc = subprocess.Popen(
    [sys.argv[1], "app-server", "--listen", "stdio://"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    text=True, bufsize=1,
)
requests = [
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-meter-smoke","version":"0.1.0"},"capabilities":{"experimentalApi":True}}},
    {"jsonrpc":"2.0","method":"initialized","params":{}},
    {"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":None},
]
for request in requests:
    proc.stdin.write(json.dumps(request) + "\n")
    proc.stdin.flush()

result = None
deadline = time.time() + 15
while time.time() < deadline and result is None:
    ready, _, _ = select.select([proc.stdout], [], [], 0.5)
    if not ready:
        continue
    line = proc.stdout.readline()
    if not line:
        break
    item = json.loads(line)
    if item.get("id") == 2:
        result = item.get("result")
proc.terminate()
if result is None:
    raise AssertionError("rate-limit response missing")
assert result and result.get("rateLimits"), "rate-limit response missing"
snapshot = result["rateLimits"]
assert snapshot.get("planType"), "plan type missing"
assert snapshot.get("primary"), "primary limit missing"
credits = result.get("rateLimitResetCredits")
print("protocol smoke OK")
print(f"plan={snapshot['planType']}")
print(f"primary_used={snapshot['primary'].get('usedPercent')}%")
print(f"reset_credits={credits.get('availableCount') if credits else 'unavailable'}")
PY
