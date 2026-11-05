# git-extras

Git hooks and PATH utilities.

## Layout

```text
git-extras/
  install-hooks             # hooks → ~/.config/git/hooks (or dest)
  install-bin               # utilities → ~/.local/bin (or dest)
  install                   # stub pointing at the two above
  bin/                      # PATH utilities (git-browse, git-colorize, git-url, lg)
  hooks/                    # user hooks (prepare-commit-msg, pre-push)
```

Git runs `git-*` on `PATH` as subcommands (`git browse`, `git colorize`). Hooks install **user-wide** via `core.hooksPath`, not per-repo.

## Install

Install utilities to `~/.local/bin` by default, or choose another directory:

```bash
./install-bin
./install-bin /other/dir
```

Ensure `~/.local/bin` is on `PATH`. After `./install-bin`, remove or replace the `~/bin` originals of `git-browse`, `git-colorize`, and `lg`, **or** ensure `~/.local/bin` precedes `~/bin` on `PATH` — otherwise the shell keeps resolving the stale copies.

Install hooks to `git config --global core.hooksPath`, or `~/.config/git/hooks` if that is unset (and set `core.hooksPath` in that case):

```bash
./install-hooks
./install-hooks /other/hooks
```

Passing an explicit destination copies files only; it does not change `core.hooksPath`.

## Test

```bash
./bin/tests/test_install_bin.sh
./bin/tests/test_git_url.sh
./hooks/tests/test_install_hooks.sh
./hooks/tests/test_prepare_commit_msg.sh
```

## Tools

- **lg** — wrap lazygit, caching git auth for the current repo (or recent lazygit projects) first. `--cache-only` skips launching lazygit.
- **git browse** — open the current remote (and optional file/line) in a browser. Supports GitHub, GitLab, and Bitbucket; works in bare repos.
- **git colorize** — run a git command (or filter a pipe) and color errors/warnings/success lines.
- **git url** — print a GitHub/GitHub Enterprise file permalink, warning if the file has uncommitted changes or HEAD is not known to be pushed.
- **prepare-commit-msg** — generate an AI commit message with `llm` unless `AICOMMIT=false` or the message was passed with `-m`.
- **pre-push** — refuse pushes of `sandbox/*` branches.

### git url

Requires Bash, Git, and standard Unix utilities (including `readlink`). After
installing with `./install-bin`, use either `git url` or `git-url`. Before
installation, use `./bin/git-url` directly.

```bash
git url docs/validation/cdm-notification-payload.md
git url /absolute/path/to/repo/docs/file.md
git url --fetch docs/file.md
git url --remote upstream docs/file.md
git url -- -file.md
```

The file's location determines the repository, so you can invoke it from
any directory. The URL uses the full HEAD commit SHA, not a moving branch.
SSH and HTTP(S) remote URLs become HTTPS links; spaces and URL metacharacters
in file paths are percent-encoded. The selected remote defaults to the current
branch's configured remote, falling back to `origin`; override it with
`--remote NAME`. The first configured fetch URL is used for the web link,
ignoring transport-only `url.*.insteadOf` rewrites. Only GitHub's `/blob/`
layout is supported, including enterprise hosts.

The URL alone goes to **stdout**, making it easy to capture:

```bash
url=$(git url docs/file.md)
```

Warnings go to **stderr** if the file has staged or unstaged changes, is absent
from HEAD (untracked or newly added), or HEAD is not known to be pushed to the
selected remote. The URL always points to the committed version, not changes
on disk. For files absent from HEAD, the best-effort URL will not resolve.
Even an unrelated unpushed commit requires a warning: this exact commit
permalink needs HEAD published, not just an older version of the file.

**Offline by default:** push checks use cached remote-tracking branch refs,
which may be stale. `--fetch` refreshes and prunes the selected remote's branch
refs before checking. A failed fetch warns and falls back to cached information.
Publication through tags alone, web permissions, and server availability are
not verified. No invocation commits or pushes changes, and only `--fetch`
contacts the remote.

Exit status is **0** when a URL is printed, including warnings, **1** when an
error prevents URL construction, and **2** for invalid arguments.
