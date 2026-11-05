# git-url design

## Purpose and interface

Add a standalone executable `bin/git-url`, also callable as `git url` when
installed on PATH. Accept one absolute or relative file path:

```text
git url [--fetch] [--remote NAME] [--] FILE
```

Print a single HTTPS GitHub/GitHub Enterprise commit permalink on stdout.
Send warnings and errors to stderr; do not open a browser. Support `--help`.
The repository is determined from the file's directory, not the caller's
working directory. Encode special characters in the repository-relative path.

## Repository and remote selection

Resolve the file's parent directory without following the final file symlink,
so a tracked symlink links to its Git entry. Require a file or symlink in a
non-bare Git worktree with a HEAD commit. Prefer the current branch's configured
remote when it names a real remote; otherwise use `origin`. Allow `--remote`
to override selection. Fail clearly when the remote is unavailable or its URL
cannot be converted to a web repository URL. Use the full `refs/heads/` branch
identity so a colliding tag does not alter remote selection. Where a remote
has multiple configured URLs, select the first fetch URL, without applying
transport-only `insteadOf` rewrites.

Support scp-style SSH, `ssh://`, HTTP, and HTTPS remote URLs. Convert to HTTPS,
remove SSH credentials/ports and any `.git` suffix, and never expose embedded
credentials in output. Use the GitHub `/blob/<HEAD SHA>/<file>` layout, including
for enterprise hosts. Other hosting providers are outside this initial scope.

## Warnings and push verification

The default is offline: no fetch or other network requests. `--fetch` explicitly
fetches the selected remote's branch refs before checking reachability. Do not
push, commit, change the index or worktree, or install anything automatically.

Warn separately when:

- The file is absent from HEAD (including untracked or newly staged files):
  the generated URL will not resolve at that commit.
- The file has staged or unstaged changes compared with HEAD: the URL refers
  to committed content, not those changes.
- HEAD is not reachable through any cached remote-tracking branch for the
  selected remote: the permalink may not resolve because the commit is not
  known to be pushed.
- No remote branch refs are available: pushed status cannot be verified.
- An explicitly requested fetch fails: use existing refs but warn that the
  refresh failed and verification is based on cached information.

Checking HEAD reachability is intentional: even if identical file content is
already pushed in another commit, this exact permalink needs HEAD published.
Local checks are evidence from cached refs, not a guarantee of current remote
state. Explain this limitation in help and README rather than warning on every
normal invocation. A remote may have changed since the last fetch; GitHub access
permissions and server availability are not verified.

Warnings do not prevent printing the best-effort URL and return exit code 0.
Invalid arguments return 2; errors that prevent URL construction return 1 and
produce no URL. A file missing on disk is an error, except a dangling symlink
can still be represented as a tracked Git entry.

## Implementation and integration

Use Bash, consistent with existing utilities. Keep the utility standalone and
avoid changes to `git-browse` or the user's installer edits. Use Git commands
with quoted arguments, literal pathspecs, and option terminators. Encode UTF-8
path bytes in Bash without adding a runtime dependency on Python or a GitHub CLI.
Standard Unix utilities, including `readlink`, are required. Preserve trailing
newlines in directory names and symlink targets. Check file content independently
of index flags, including hashing symlink targets without following them.
Existing `install-bin` discovers executable files automatically.

Document usage, dependency requirements, warnings, cached-ref limitations, and
the new test command in README. Extend the installer test's executable list.

## Verification

Add a shell integration suite using isolated temporary worktrees and bare
remotes, with Git identity and hooks controlled by the tests. Temporary files
use `${TMPDIR:-/tmp}`, not a directory specific to the agent harness. Cover clean,
staged, unstaged, untracked, newly staged, and unpushed states; file versus HEAD
reachability; missing cached refs; successful and failed explicit fetches;
absolute and relative paths outside the caller's repo; detached HEAD; remote
selection and URL formats; spaces, URL metacharacters, and leading dashes in
paths; invalid inputs; stdout/stderr separation; help; and installation.

Run Bash syntax checks, the new suite, and the existing installer suite. Run
ShellCheck if available. Do not modify or commit unrelated existing work.
