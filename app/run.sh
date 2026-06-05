#!/usr/bin/env bash
# Always run exactly ONE fresh instance. Avoids stale menu-bar instances
# holding the ⌃⌘Space hotkey (the first registrant wins it system-wide).
set -e
cd "$(dirname "$0")"
pkill -9 -x zforfinder 2>/dev/null || true
sleep 0.5
swift build
nohup ./.build/debug/zforfinder >/tmp/zff.log 2>&1 &
sleep 1
echo "running instances: $(pgrep -x zforfinder | wc -l | tr -d ' ')  (log: /tmp/zff.log)"
