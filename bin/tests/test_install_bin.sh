#!/usr/bin/env bash
# Self-check for ./install-bin (source tree only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$ROOT/install-bin" "$TMP/out"
for name in git-browse git-colorize lg; do
  test -x "$TMP/out/$name" || { echo "missing or not executable: $name" >&2; exit 1; }
done

# Subdir contents must not be installed
test ! -e "$TMP/out/tests"

echo "self-test: ok (install-bin)"
