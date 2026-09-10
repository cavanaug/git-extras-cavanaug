# git-extras

Git hooks and PATH utilities.

## Layout

```text
git-extras/
  install-hooks             # hooks → ~/.config/git/hooks (or dest)
  install-bin               # utilities → ~/.local/bin (or dest)
  install                   # stub pointing at the two above
  bin/                      # PATH utilities (git-browse, git-colorize)
  hooks/                    # user hooks (prepare-commit-msg, pre-push)
```

Git runs `git-*` on `PATH` as subcommands (`git browse`, `git colorize`). Hooks install **user-wide** via `core.hooksPath`, not per-repo.

## Install

Install utilities to `~/.local/bin` by default, or choose another directory:

```bash
./install-bin
./install-bin /other/dir
```

Ensure `~/.local/bin` is on `PATH`. After `./install-bin`, remove or replace the `~/bin` originals of `git-browse` and `git-colorize`, **or** ensure `~/.local/bin` precedes `~/bin` on `PATH` — otherwise the shell keeps resolving the stale copies.

Install hooks to `git config --global core.hooksPath`, or `~/.config/git/hooks` if that is unset (and set `core.hooksPath` in that case):

```bash
./install-hooks
./install-hooks /other/hooks
```

Passing an explicit destination copies files only; it does not change `core.hooksPath`.

## Test

```bash
./bin/tests/test_install_bin.sh
./hooks/tests/test_install_hooks.sh
./hooks/tests/test_prepare_commit_msg.sh
```

## Tools

- **git browse** — open the current remote (and optional file/line) in a browser. Supports GitHub, GitLab, and Bitbucket; works in bare repos.
- **git colorize** — run a git command (or filter a pipe) and color errors/warnings/success lines.
- **prepare-commit-msg** — generate an AI commit message with `llm` unless `AICOMMIT=false` or the message was passed with `-m`.
- **pre-push** — refuse pushes of `sandbox/*` branches.
