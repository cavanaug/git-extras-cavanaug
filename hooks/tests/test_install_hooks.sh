#!/usr/bin/env bash
# Self-check for ./install-hooks (source tree only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE_CONFIG="$TMP/gitconfig"
touch "$FAKE_CONFIG"
export GIT_CONFIG_GLOBAL="$FAKE_CONFIG"
export GIT_CONFIG_NOSYSTEM=1

DEST="$TMP/hooks"
"$ROOT/install-hooks" "$DEST"
for name in prepare-commit-msg pre-push; do
  test -x "$DEST/$name" || { echo "missing or not executable: $name" >&2; exit 1; }
done

# Subdir contents must not be installed
test ! -e "$DEST/tests"

# Explicit dest must not mutate git config
if git config --global --get core.hooksPath >/dev/null 2>&1; then
  echo "install-hooks wrote core.hooksPath despite explicit dest" >&2
  exit 1
fi

# No dest: install to ~/.config/git/hooks and set core.hooksPath
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME"
HOME="$FAKE_HOME"
GIT_CONFIG_GLOBAL="$FAKE_HOME/.gitconfig"
touch "$GIT_CONFIG_GLOBAL"
"$ROOT/install-hooks"
for name in prepare-commit-msg pre-push; do
  test -x "$FAKE_HOME/.config/git/hooks/$name" || { echo "default dest missing: $name" >&2; exit 1; }
done
got="$(git config --global --get core.hooksPath)"
want="$FAKE_HOME/.config/git/hooks"
if [[ "$got" != "$want" ]]; then
  echo "core.hooksPath: got $got want $want" >&2
  exit 1
fi

# No dest: honor an existing core.hooksPath and do not rewrite it
CUSTOM="$TMP/custom-hooks"
git config --global core.hooksPath "$CUSTOM"
"$ROOT/install-hooks"
for name in prepare-commit-msg pre-push; do
  test -x "$CUSTOM/$name" || { echo "hooksPath dest missing: $name" >&2; exit 1; }
done
got="$(git config --global --get core.hooksPath)"
if [[ "$got" != "$CUSTOM" ]]; then
  echo "core.hooksPath rewritten: got $got want $CUSTOM" >&2
  exit 1
fi

echo "self-test: ok (install-hooks)"
