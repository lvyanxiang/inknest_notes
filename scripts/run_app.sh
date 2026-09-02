#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

if [[ ! -f .env.flutter ]]; then
  echo "Missing .env.flutter. Create your local API origin first:" >&2
  echo "  cp .env.flutter.example .env.flutter" >&2
  exit 1
fi

args=("$@")

has_device_flag=0
for arg in "${args[@]+"${args[@]}"}"; do
  case "$arg" in
    -d|--device-id|-d=*|--device-id=*)
      has_device_flag=1
      break
      ;;
  esac
done

# Prefer an explicit DEVICE=… from make when -d was not already passed.
if [[ $has_device_flag -eq 0 && -n "${DEVICE:-}" ]]; then
  args=(-d "$DEVICE" "${args[@]+"${args[@]}"}")
  has_device_flag=1
fi

# When no device was chosen, list connected targets and ask interactively.
if [[ $has_device_flag -eq 0 ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to list devices for selection." >&2
    exit 1
  fi

  device_tsv="$(
    flutter devices --machine | python3 -c '
import json
import sys

try:
    devices = json.load(sys.stdin)
except json.JSONDecodeError as error:
    print(f"Unable to parse flutter devices --machine: {error}", file=sys.stderr)
    sys.exit(1)

rows = []
for device in devices:
    device_id = device.get("id")
    if not device_id:
        continue
    name = device.get("name") or device_id
    platform = device.get("targetPlatform") or device.get("platform") or ""
    emulator = device.get("emulator")
    kind = "emulator/simulator" if emulator else "device"
    epilog = f"{platform}, {kind}" if platform else kind
    rows.append((device_id, f"{name} ({epilog})"))

if not rows:
    print(
        "No Flutter devices found. Connect a phone, start a simulator, or pass -d.",
        file=sys.stderr,
    )
    sys.exit(2)

for device_id, label in rows:
    print(f"{device_id}\t{label}")
'
  )"

  device_ids=()
  device_labels=()
  while IFS=$'\t' read -r device_id device_label; do
    [[ -z "${device_id:-}" ]] && continue
    device_ids+=("$device_id")
    device_labels+=("$device_label")
  done <<<"$device_tsv"

  if [[ ${#device_ids[@]} -eq 0 ]]; then
    echo "No Flutter devices found. Connect a phone, start a simulator, or pass -d." >&2
    exit 2
  fi

  if [[ ${#device_ids[@]} -eq 1 ]]; then
    echo "Using only available target: ${device_labels[0]}"
    args=(-d "${device_ids[0]}" "${args[@]+"${args[@]}"}")
  else
    echo "Connected devices:"
    for index in "${!device_ids[@]}"; do
      printf '  [%d] %s\n' "$((index + 1))" "${device_labels[$index]}"
    done
    echo "  [q] Quit"
    while true; do
      read -r -p "Choose a device [1-${#device_ids[@]}]: " choice
      if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
        exit 0
      fi
      if [[ "$choice" =~ ^[0-9]+$ ]] &&
        ((choice >= 1 && choice <= ${#device_ids[@]})); then
        selected_index=$((choice - 1))
        echo "Launching on: ${device_labels[$selected_index]}"
        args=(-d "${device_ids[$selected_index]}" "${args[@]+"${args[@]}"}")
        break
      fi
      echo "Invalid choice. Enter a number 1-${#device_ids[@]}, or q to quit." >&2
    done
  fi
fi

exec flutter run --dart-define-from-file=.env.flutter "${args[@]}"
