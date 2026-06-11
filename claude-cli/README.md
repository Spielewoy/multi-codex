# claude-cli — Claude Code

**Strategy:** `env` — sets `CLAUDE_CONFIG_DIR={profileDir}` before launch.

Claude Code reads its entire config tree (settings, credentials, history, MCP state, plugins) from `CLAUDE_CONFIG_DIR`, defaulting to `~/.claude/`. Per-profile dirs give clean account isolation.

## Install

```bash
npm i -g @anthropic-ai/claude-code
```

## Quickstart

```bash
multi-cli new claude-cli/work
multi-cli new claude-cli/personal
claude-cli-work       # /login on first run
claude-cli-personal   # different account; runs concurrently
```

## Profile types

- **full** *(default)* — separate `settings.json`, `.credentials.json`, `skills/`, `agents/`, `plugins/`, `commands/`, `todos/`, `projects/`, `history.jsonl`.
- **shared** — symlinks `settings.json`, `skills/`, `agents/`, `plugins/`, `commands/` from `~/.claude/`. Only credentials and history stay isolated.

## Continue a chat across accounts

Rate-limited on one account? Copy the conversation state to a profile logged into another, then resume the same chat.

```bash
multi-cli continue claude-cli work personal   # copy sessions/history (never credentials)
claude-cli-personal
claude --resume <session-id>                   # run from the same project directory
```

`base` works as either profile name and means `~/.claude`. Default merge keeps newer destination files; `--no-merge` overwrites, `--dry-run` previews.

## Verified

Smoke-tested live against `Claude Code 2.1.143` on Windows.
