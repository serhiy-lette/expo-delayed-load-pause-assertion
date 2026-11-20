#!/usr/bin/env bash
# Usage: ./repro.sh [runs]   (default 8)
# Needs: the release APK installed on a running Android emulator, and `node hang-server.js` running.
set -u
PKG=dev.repro.delayedload
RUNS=${1:-8}
crashes=0

for n in $(seq 1 "$RUNS"); do
  adb shell am force-stop "$PKG"
  adb logcat -c
  # First instance. Its delayed load now waits for the update check.
  adb shell am start -n "$PKG/.MainActivity" >/dev/null
  sleep 1.5
  # Second instance, in its own task, while the first one is still waiting.
  adb shell am start --activity-multiple-task -n "$PKG/.MainActivity" >/dev/null
  sleep 11
  order=$(adb logcat -d | grep -oE 'ReactHost\{[0-9]+\}\.onHost(Resume|Pause)\(activity\)' |
    sed -E 's/.*onHost(Resume|Pause).*/\1/' | tr '\n' ' ')
  adb shell input keyevent HOME
  sleep 3
  if adb logcat -d | grep -q 'Pausing an activity that is not the current activity'; then
    result=CRASH
    crashes=$((crashes + 1))
  else
    result=ok
  fi
  echo "run $n: ReactHost calls before Home: [ $order] -> $result"
done

echo "$crashes of $RUNS runs crashed"
