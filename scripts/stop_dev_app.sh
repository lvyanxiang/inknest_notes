#!/usr/bin/env bash
set -euo pipefail

# Free Flutter / iOS device-debug leftovers so `make run` can attach again.
# Does not uninstall the App or wipe local notebook data.

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

compact_pids() {
  tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

echo "Stopping stale iOS debug port forwards (iproxy)..."
iproxy_pids="$(pgrep -x iproxy 2>/dev/null | compact_pids || true)"
if [[ -n "${iproxy_pids}" ]]; then
  echo "  iproxy: ${iproxy_pids}"
  # shellcheck disable=SC2086
  kill ${iproxy_pids} 2>/dev/null || true
  sleep 0.3
  # shellcheck disable=SC2086
  kill -9 ${iproxy_pids} 2>/dev/null || true
else
  echo "  no iproxy listeners"
fi

echo "Stopping leftover Flutter run sessions for this project..."
# Match both `flutter run` and the Dart snapshot Flutter actually launches.
flutter_pids="$(
  {
    pgrep -f "flutter_tools.snapshot run" 2>/dev/null || true
    pgrep -f "flutter run" 2>/dev/null || true
    pgrep -f "${root_dir}/scripts/run_app.sh" 2>/dev/null || true
  } | sort -u | awk 'NF && $1 ~ /^[0-9]+$/'
)"
flutter_pids="$(printf '%s\n' "${flutter_pids}" | compact_pids)"
if [[ -n "${flutter_pids}" ]]; then
  echo "  flutter: ${flutter_pids}"
  # shellcheck disable=SC2086
  kill ${flutter_pids} 2>/dev/null || true
  sleep 0.5
  # shellcheck disable=SC2086
  kill -9 ${flutter_pids} 2>/dev/null || true
else
  echo "  no Flutter run sessions"
fi

if command -v xcrun >/dev/null 2>&1; then
  echo "Checking CoreDeviceService..."
  if ! xcrun devicectl list devices >/dev/null 2>&1; then
    core_pids="$(pgrep -f 'CoreDeviceService' 2>/dev/null | compact_pids || true)"
    if [[ -n "${core_pids}" ]]; then
      echo "  restarting hung CoreDeviceService: ${core_pids}"
      # shellcheck disable=SC2086
      kill ${core_pids} 2>/dev/null || true
      sleep 1
    else
      echo "  CoreDeviceService not running; launchd should respawn it"
    fi
    xcrun devicectl list devices >/dev/null 2>&1 || true
  else
    echo "  CoreDeviceService responds"
  fi
fi

echo "Flutter debug helpers cleared."
