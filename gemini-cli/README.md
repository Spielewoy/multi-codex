# gemini-cli — Gemini CLI

**Strategy:** `env` — sets `GEMINI_CLI_HOME={profileDir}` before launch.

The official Gemini CLI honors `GEMINI_CLI_HOME` to relocate its `.gemini/` config tree (settings, OAuth credentials, history, skills).

## Install

```bash
npm i -g @google/gemini-cli
```

## Quickstart

```bash
multi-cli new gemini-cli/work
multi-cli new gemini-cli/personal
gemini-cli-work
gemini-cli-personal
```

## Profile types

- **full** *(default)* — separate `oauth_creds.json`, `google_accounts.json`, `settings.json`, `history/`, `skills/`.
- **shared** — symlinks `settings.json`, `skills/`, `GEMINI.md` from `~/.gemini/`. Only OAuth state stays isolated.

## Continue a chat across accounts

Rate-limited on one account? Copy the conversation state to a profile logged into another, then resume the same chat.

```bash
multi-cli continue gemini-cli work personal   # copy sessions/history (never OAuth)
gemini-cli-personal
gemini --resume                                # or /chat resume inside the session
```

`base` works as either profile name and means `~/.gemini`. Default merge keeps newer destination files; `--no-merge` overwrites, `--dry-run` previews.

## Verified

Smoke-tested live on Windows after `npm i -g @google/gemini-cli`. Specific binary version recorded in `tests/results.md` after the test run.
