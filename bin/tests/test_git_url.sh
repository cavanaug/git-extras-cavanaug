#!/usr/bin/env bash
# Integration tests: real Git repositories and local transports only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLI="$ROOT/bin/git-url"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/git-url-test.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/gitconfig"
export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_TERMINAL_PROMPT=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_CONFIG_COUNT
mkdir -p "$HOME"
git config --global core.hooksPath /dev/null
git config --global commit.gpgSign false
git config --global protocol.file.allow always

fail() { printf 'FAIL (%s): %s\n' "$case_name" "$*" >&2; exit 1; }
contains() { grep -Fqi -- "$2" "$1" || fail "expected '$2' in $(cat "$1")"; }
empty() { [[ ! -s $1 ]] || fail "expected empty output: $(cat "$1")"; }
run_cli() {
    if "$CLI" "$@" >"$TMP/out" 2>"$TMP/err"; then status=0; else status=$?; fi
}
success_url() {
    [[ $status == 0 ]] || fail "exit $status: $(cat "$TMP/err")"
    [[ $(cat "$TMP/out") == "https://github.example/owner/repo/blob/$head/$1" ]] ||
        fail "unexpected URL: $(cat "$TMP/out")"
    [[ $(wc -l <"$TMP/out") == 1 ]] || fail 'stdout must contain exactly one line'
}
error() {
    [[ $status == "$1" ]] || fail "expected exit $1, got $status"
    empty "$TMP/out"
    [[ -s $TMP/err ]] || fail 'missing error message'
}
fixture() {
    repo="$TMP/$case_name/work"
    bare="$TMP/$case_name/remote.git"
    mkdir -p "$repo"
    git init -q --initial-branch=main "$repo"
    git init -q --bare "$bare"
    cd "$repo"
    mkdir docs
    printf 'committed\n' >docs/file.md
    git add .
    git commit -qm initial
    head="$(git rev-parse HEAD)"
    git remote add origin https://github.example/owner/repo.git
    # Keep web URL configuration real while routing transport to a local remote.
    git config "url.$bare.insteadOf" https://github.example/owner/repo.git
    git push -qu origin main
}
commit_file() { git add -- "$1"; git commit -qm 'add file'; head="$(git rev-parse HEAD)"; git push -q origin main; }

test_clean() { run_cli docs/file.md; success_url docs/file.md; empty "$TMP/err"; }
test_absolute_outside() { cd "$TMP"; run_cli "$repo/docs/file.md"; success_url docs/file.md; empty "$TMP/err"; }
test_relative_subdirectory() { cd docs; run_cli ../docs/file.md; success_url docs/file.md; empty "$TMP/err"; }
test_unstaged() { echo dirty >>docs/file.md; run_cli docs/file.md; success_url docs/file.md; contains "$TMP/err" uncommitted; }
test_staged() { echo staged >>docs/file.md; git add docs/file.md; run_cli docs/file.md; success_url docs/file.md; contains "$TMP/err" uncommitted; }
test_index_differs_only() {
    echo staged >>docs/file.md; git add docs/file.md; printf 'committed\n' >docs/file.md
    run_cli docs/file.md; success_url docs/file.md; contains "$TMP/err" uncommitted
}
test_assume_unchanged() {
    git update-index --assume-unchanged docs/file.md
    echo dirty >>docs/file.md
    run_cli docs/file.md; success_url docs/file.md; contains "$TMP/err" uncommitted
}
test_skip_worktree() {
    git update-index --skip-worktree docs/file.md
    echo dirty >>docs/file.md
    run_cli docs/file.md; success_url docs/file.md; contains "$TMP/err" uncommitted
}
test_untracked() { echo new >new.md; run_cli new.md; success_url new.md; contains "$TMP/err" 'absent from HEAD'; }
test_newly_staged() { echo new >new.md; git add new.md; run_cli new.md; success_url new.md; contains "$TMP/err" 'absent from HEAD'; }
test_unpushed() {
    echo new >>docs/file.md; git commit -qam change; head="$(git rev-parse HEAD)"
    run_cli docs/file.md; success_url docs/file.md; contains "$TMP/err" 'not known to be pushed'
}
test_unrelated_unpushed() {
    echo new >other; git add other; git commit -qm unrelated; head="$(git rev-parse HEAD)"
    run_cli docs/file.md; success_url docs/file.md; contains "$TMP/err" 'not known to be pushed'
}
test_published_descendant() {
    echo new >other; git add other; git commit -qm descendant; git push -q origin main
    git checkout -q --detach "$head"
    run_cli docs/file.md; success_url docs/file.md; empty "$TMP/err"
}
test_no_refs() {
    git update-ref -d refs/remotes/origin/main
    run_cli docs/file.md; success_url docs/file.md; contains "$TMP/err" 'cannot verify'
}
test_symbolic_ref_not_evidence() {
    git symbolic-ref refs/remotes/origin/HEAD refs/heads/main
    git update-ref -d refs/remotes/origin/main
    run_cli docs/file.md; success_url docs/file.md; contains "$TMP/err" 'cannot verify'
}
test_fetch() {
    git update-ref -d refs/remotes/origin/main
    run_cli --fetch docs/file.md; success_url docs/file.md; empty "$TMP/err"
    [[ $(git rev-parse refs/remotes/origin/main) == "$head" ]] || fail 'fetch did not refresh refs'
}
test_fetch_failure() {
    git config "url.$bare.insteadOf" https://not-used.invalid/
    git config "url.$TMP/missing.git.insteadOf" https://github.example/owner/repo.git
    run_cli --fetch docs/file.md; success_url docs/file.md; contains "$TMP/err" 'fetch failed'
}
test_default_offline() {
    git update-ref -d refs/remotes/origin/main
    run_cli docs/file.md; success_url docs/file.md; contains "$TMP/err" 'cannot verify'
    if git show-ref --verify --quiet refs/remotes/origin/main; then fail 'default invocation fetched'; fi
}
test_fetch_prunes() {
    git update-ref refs/remotes/origin/obsolete "$head"
    git update-ref -d refs/remotes/origin/main
    git --git-dir="$bare" update-ref -d refs/heads/main
    run_cli --fetch docs/file.md; success_url docs/file.md; contains "$TMP/err" 'cannot verify'
}
test_no_mutation() {
    echo staged >staged; git add staged; echo dirty >>docs/file.md
    before="$(git status --porcelain=v1)"; index_before="$(git write-tree)"
    run_cli docs/file.md; success_url docs/file.md
    [[ $(git status --porcelain=v1) == "$before" && $(git write-tree) == "$index_before" ]] || fail 'mutated worktree or index'
}
test_encoding() {
    name='docs/a b#?%[x]é.md'; echo special >"$name"; commit_file "$name"
    run_cli "$name"; success_url 'docs/a%20b%23%3F%25%5Bx%5D%C3%A9.md'; empty "$TMP/err"
}
test_literal_pathspec() {
    echo literal >'docs/[x].md'; commit_file 'docs/[x].md'
    echo other >docs/x.md; git add docs/x.md
    run_cli 'docs/[x].md'; success_url 'docs/%5Bx%5D.md'; empty "$TMP/err"
}
test_leading_dash() { echo dash >-file; commit_file -file; run_cli -- -file; success_url -file; empty "$TMP/err"; }
test_symlink() {
    ln -s "$TMP/nonexistent" link; commit_file link
    run_cli link; success_url link; empty "$TMP/err"
}
test_directory_symlink() {
    ln -s "$repo/docs" "$TMP/docs-link"
    run_cli "$TMP/docs-link/file.md"; success_url docs/file.md; empty "$TMP/err"
}
test_other_remote() {
    git remote rename origin upstream
    run_cli docs/file.md; success_url docs/file.md; empty "$TMP/err"
}
test_multiple_urls() {
    git remote set-url --add origin https://github.example/other/wrong.git
    run_cli docs/file.md; success_url docs/file.md; empty "$TMP/err"
}
test_multiple_urls_fetch() {
    git remote set-url --add origin https://github.example/other/wrong.git
    git update-ref -d refs/remotes/origin/main
    run_cli --fetch docs/file.md; success_url docs/file.md; empty "$TMP/err"
}
test_ambiguous_branch() {
    git remote rename origin upstream
    git remote add origin https://github.example/other/wrong.git
    git tag main
    run_cli docs/file.md; success_url docs/file.md; empty "$TMP/err"
}
test_newline_directory() {
    mkdir $'trailing\n'
    printf 'committed\n' >$'trailing\n/file.md'
    commit_file $'trailing\n/file.md'
    run_cli $'trailing\n/file.md'; success_url 'trailing%0A/file.md'; empty "$TMP/err"
}
test_newline_worktree_root() {
    cd "$TMP"
    mv "$repo" "$repo"$'\n'
    repo+=$'\n'
    cd "$repo"
    run_cli docs/file.md; success_url docs/file.md; empty "$TMP/err"
}
test_hidden_symlink_change() {
    ln -s old-target link; commit_file link
    git update-index --assume-unchanged link
    rm link; ln -s new-target link
    run_cli link; success_url link; contains "$TMP/err" uncommitted
}
test_skip_worktree_symlink() {
    ln -s old-target link; commit_file link
    git update-index --skip-worktree link
    rm link; ln -s new-target link
    run_cli link; success_url link; contains "$TMP/err" uncommitted
}
test_newline_symlink_target() {
    ln -s $'target\n' link; commit_file link
    git update-index --assume-unchanged link
    run_cli link; success_url link; empty "$TMP/err"
}
test_remote_override() {
    git remote add alternate git@github.example:owner/repo.git
    git update-ref refs/remotes/alternate/main "$head"
    run_cli --remote alternate docs/file.md; success_url docs/file.md; empty "$TMP/err"
}
test_missing_upstream_remote() {
    git config branch.main.remote missing
    run_cli docs/file.md; success_url docs/file.md; empty "$TMP/err"
}
test_ssh() {
    git config remote.origin.url ssh://git@github.example:2222/owner/repo.git
    run_cli docs/file.md; success_url docs/file.md; empty "$TMP/err"
}
test_scp() {
    git config remote.origin.url git@github.example:owner/repo.git
    run_cli docs/file.md; success_url docs/file.md; empty "$TMP/err"
}
test_http_credentials() {
    git config remote.origin.url http://user:secret@github.example/owner/repo.git
    run_cli docs/file.md; success_url docs/file.md; empty "$TMP/err"
}
test_https_port() {
    git config remote.origin.url https://user:secret@github.example:8443/owner/repo.git
    run_cli docs/file.md
    [[ $status == 0 && $(cat "$TMP/out") == "https://github.example:8443/owner/repo/blob/$head/docs/file.md" ]] || fail 'HTTPS port not preserved'
    empty "$TMP/err"
}
test_linked_worktree() {
    git worktree add -q --detach "$TMP/linked" HEAD
    run_cli "$TMP/linked/docs/file.md"; success_url docs/file.md; empty "$TMP/err"
}
test_not_repo() { echo plain >"$TMP/plain"; run_cli "$TMP/plain"; error 1; }
test_missing_file() { run_cli docs/missing; error 1; }
test_directory() { run_cli docs; error 1; }
test_missing_remote() { run_cli --remote missing docs/file.md; error 1; }
test_local_remote() { git config remote.origin.url "$bare"; run_cli docs/file.md; error 1; }
test_invalid_remote_url() {
    git config remote.origin.url 'https://user:secret@github.example/owner/repo?token=secret'
    run_cli docs/file.md; error 1
    if grep -q secret "$TMP/out" "$TMP/err"; then fail 'credential leak'; fi
}
test_no_head() {
    git init -q "$TMP/empty"; echo new >"$TMP/empty/file"
    run_cli "$TMP/empty/file"; error 1
}
test_usage() { run_cli; error 2; run_cli --unknown docs/file.md; error 2; run_cli --remote; error 2; run_cli a b; error 2; }
test_help() { run_cli --help; [[ $status == 0 ]] || fail 'help failed'; contains "$TMP/out" Usage; empty "$TMP/err"; }

case_name=executable
[[ -x $CLI ]] || fail 'git-url executable is missing'
count=0
cases=(clean absolute_outside relative_subdirectory unstaged staged index_differs_only
    assume_unchanged skip_worktree
    untracked newly_staged unpushed unrelated_unpushed published_descendant no_refs
    symbolic_ref_not_evidence fetch fetch_failure default_offline fetch_prunes no_mutation
    encoding literal_pathspec leading_dash symlink directory_symlink other_remote
    remote_override missing_upstream_remote ssh scp http_credentials https_port linked_worktree
    not_repo missing_file directory missing_remote local_remote invalid_remote_url no_head usage help
    multiple_urls multiple_urls_fetch ambiguous_branch newline_directory newline_worktree_root
    hidden_symlink_change skip_worktree_symlink newline_symlink_target)
# Optional case names make individual regression failures easy to reproduce.
if [[ $# -gt 0 ]]; then cases=("$@"); fi
for case_name in "${cases[@]}"; do
    fixture
    "test_$case_name"
    count=$((count + 1))
    printf 'ok %s - %s\n' "$count" "$case_name"
done
printf 'self-test: ok (git-url, %s cases)\n' "$count"
