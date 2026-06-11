# commandcode — Command Code

**Strategy:** `redirectHome` — launches with `HOME` / `USERPROFILE` redirected to a per-profile fake home, then symlinks shared dotfiles back from the real home.

Command Code resolves its config dir from `os.homedir()` with no override env var. Redirecting the home directory is the only way to fully isolate `~/.commandcode/`. Shared dotfiles like `~/.gitconfig`, `~/.ssh/`, and `~/.npmrc` are symlinked back into the fake home so child processes (git, ssh, npm) keep working.

## Install

```bash
npm i -g commandcode
```

## Quickstart

```bash
multi-cli new commandcode/work
multi-cli new commandcode/personal
commandcode-work
commandcode-personal
```

## Profile types

- **full** *(default)* — separate `auth.json`, `history.jsonl`, `projects/`, `file-history/`, `skills/`, `taste/`, `plans/`.
- **shared** — symlinks `skills/`, `taste/`, `plans/` from `~/.commandcode/`. Auth and history stay isolated.

## Continue a chat across accounts

Rate-limited on one account? Copy the conversation state to a profile logged into another, then resume the same chat.

```bash
multi-cli continue commandcode work personal   # copy history/projects (never auth)
commandcode-personal                            # resume from the same working directory
```

`base` works as either profile name and means `~/.commandcode`. Default merge keeps newer destination files; `--no-merge` overwrites, `--dry-run` previews.

## Caveats

- Tools that read `~/.gitconfig`, `~/.ssh/`, etc. will work — they're symlinked through.
- Tools that read other dotfiles you forgot to whitelist will see an empty home. Add their dotfile names to `shareFromRealHome` in `tools/commandcode/adapter.json` if needed.

## Verified

Smoke-tested live against `Command Code 0.26.8` on Windows.
