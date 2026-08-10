#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

if [[ ! -f .env.flutter ]]; then
  echo "Missing .env.flutter. Create your local API origin first:" >&2
  echo "  cp .env.flutter.example .env.flutter" >&2
  exit 1
fi

exec flutter run --dart-define-from-file=.env.flutter "$@"
