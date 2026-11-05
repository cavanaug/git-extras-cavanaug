#!/usr/bin/env bash
# Self-check for hooks/prepare-commit-msg (source tree only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/prepare-commit-msg"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PATH_DIR="$TMP/bin"
mkdir -p "$PATH_DIR"
ARGS_FILE="$TMP/llm-args"
CALLS_FILE="$TMP/llm-calls"
: >"$CALLS_FILE"

cat >"$PATH_DIR/llm" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "${LLM_ARGS_FILE:?}"
echo 1 >> "${LLM_CALLS_FILE:?}"
echo "generated message"
exit "${LLM_EXIT:-0}"
EOF
chmod +x "$PATH_DIR/llm"

export LLM_ARGS_FILE="$ARGS_FILE"
export LLM_CALLS_FILE="$CALLS_FILE"
export PATH="$PATH_DIR:$PATH"
unset AICOMMIT AICOMMIT_MODEL AICOMMIT_REASONING_EFFORT AICOMMIT_MODEL_COMPARE

FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME"
export HOME="$FAKE_HOME"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
touch "$GIT_CONFIG_GLOBAL"

init_repo() {
  local repo="$1"
  git init -q "$repo"
  git -C "$repo" config user.email t@t
  git -C "$repo" config user.name t
}

# Default model is openai-codex/gpt-6-luna (llm models: OpenAI Codex)
REPO="$TMP/repo"
init_repo "$REPO"
echo a >"$REPO/f"
git -C "$REPO" add f
MSG="$TMP/COMMIT_EDITMSG"
echo "# template" >"$MSG"
(
  cd "$REPO"
  "$HOOK" "$MSG" "" ""
) >/dev/null

grep -q -- '--no-stream' "$ARGS_FILE" || { echo "missing --no-stream" >&2; exit 1; }
grep -qx -- '-t' "$ARGS_FILE" || { echo "missing -t" >&2; exit 1; }
grep -qx -- 'ai-commit' "$ARGS_FILE" || { echo "missing ai-commit template" >&2; exit 1; }
grep -qx -- '-m' "$ARGS_FILE" || { echo "missing -m" >&2; exit 1; }
grep -qx -- 'openai-codex/gpt-6-luna' "$ARGS_FILE" || {
  echo "default model is not openai-codex/gpt-6-luna:" >&2
  cat "$ARGS_FILE" >&2
  exit 1
}

# Empty staged diff: do not call llm
: >"$CALLS_FILE"
rm -f "$ARGS_FILE"
EMPTY="$TMP/empty"
init_repo "$EMPTY"
git -C "$EMPTY" commit -q --allow-empty -m init
echo "# template" >"$MSG"
(
  cd "$EMPTY"
  "$HOOK" "$MSG" "" ""
) >/dev/null
if [[ -s "$CALLS_FILE" ]]; then
  echo "llm called with empty staged diff" >&2
  exit 1
fi

# llm failure aborts the hook (exit 1), same as hg-aicommit
: >"$CALLS_FILE"
FAIL="$TMP/fail"
init_repo "$FAIL"
echo a >"$FAIL/f"
git -C "$FAIL" add f
echo "# template" >"$MSG"
set +e
(
  cd "$FAIL"
  LLM_EXIT=1 "$HOOK" "$MSG" "" ""
) >/dev/null
fail_status=$?
set -e
if [[ "$fail_status" -ne 1 ]]; then
  echo "llm failure: expected exit 1, got $fail_status" >&2
  exit 1
fi

# Dual-model compare path is gone (hg-aicommit has none)
if grep -q AICOMMIT_MODEL_COMPARE "$HOOK"; then
  echo "hook still has AICOMMIT_MODEL_COMPARE" >&2
  exit 1
fi

echo "self-test: ok (prepare-commit-msg)"
