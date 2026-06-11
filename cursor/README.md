# cursor — Cursor IDE

**Strategy:** `userDataDir` — passes `--user-data-dir={profileDir}` and `--extensions-dir={profileDir}/extensions` on launch.

Cursor inherits VS Code's launch flags. Each profile gets its own user data dir (settings, auth, recent workspaces, agent state) and its own extensions directory.

## Install

[cursor.com/download](https://cursor.com/download)

## Quickstart

```bash
multi-cli new cursor/work
multi-cli new cursor/personal
cursor-work       # opens a Cursor window logged in as account A
cursor-personal   # second window, account B — both run side-by-side
```

## Profile types

- **full** *(default)* — separate user data dir, separate extensions dir.
- **shared** — symlinks `sandbox.json` and `cli-config.json` from `~/.cursor/`. Auth and workspace state stay isolated.

## Continue a chat across accounts

Not supported. Cursor keeps chats in SQLite keyed to the workspace path, so they can't be portably copied between profiles. `multi-cli continue cursor …` is therefore unavailable.

## Caveats

- Cursor's cloud sync, if enabled, can re-merge state between profiles. Disable sync per-profile after first login if you want hard isolation.
- Re-indexing happens once per fresh profile; expect a few seconds of CPU on first launch.

## Verified

Smoke-tested live against `Cursor 2.0.60` on Windows.
